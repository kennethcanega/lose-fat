import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthJourneyApp());
}

class HealthJourneyApp extends StatelessWidget {
  const HealthJourneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Family Growth Tracker',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const AppBootstrapper(),
    );
  }
}

enum WeightUnit { kg, lbs }

enum HeightUnit { cm, ft }

extension WeightUnitX on WeightUnit {
  String get label => this == WeightUnit.kg ? 'kg' : 'lbs';
}

extension HeightUnitX on HeightUnit {
  String get label => this == HeightUnit.cm ? 'cm' : 'ft';
}

class UnitConverter {
  static double fromDisplayWeight(double value, WeightUnit unit) =>
      unit == WeightUnit.kg ? value : value / 2.2046226218;

  static double toDisplayWeight(double kg, WeightUnit unit) =>
      unit == WeightUnit.kg ? kg : kg * 2.2046226218;

  static double fromDisplayHeight(double value, HeightUnit unit) =>
      unit == HeightUnit.cm ? value : value * 30.48;

  static double toDisplayHeight(double cm, HeightUnit unit) =>
      unit == HeightUnit.cm ? cm : cm / 30.48;
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  bool _loading = true;
  List<GrowthProfile> _profiles = [];
  int? _selectedProfileId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ProfileRepository.instance.init();
    final profiles = await ProfileRepository.instance.fetchProfiles();
    final selectedId = await ProfileRepository.instance.getSelectedProfileId();
    setState(() {
      _profiles = profiles;
      _selectedProfileId = selectedId;
      _loading = false;
    });
  }

  Future<void> _createProfile(CreateProfileInput input) async {
    await ProfileRepository.instance.createProfile(input);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_profiles.isEmpty) {
      return RegistrationScreen(onCreateProfile: _createProfile);
    }

    return TrackerDashboard(
      profiles: _profiles,
      selectedProfileId: _selectedProfileId,
      onDataChanged: _load,
      onSelectProfile: (profileId) async {
        await ProfileRepository.instance.setSelectedProfileId(profileId);
        setState(() => _selectedProfileId = profileId);
      },
      onCreateProfile: _createProfile,
    );
  }
}

class GrowthProfile {
  const GrowthProfile({
    required this.id,
    required this.name,
    required this.purpose,
    required this.birthDate,
    required this.weightUnit,
    required this.heightUnit,
    required this.entries,
  });

  final int id;
  final String name;
  final String purpose;
  final DateTime birthDate;
  final WeightUnit weightUnit;
  final HeightUnit heightUnit;
  final List<MetricEntry> entries;

  int get ageInMonths {
    final now = DateTime.now();
    return (now.year - birthDate.year) * 12 + now.month - birthDate.month;
  }

  double get ageInYears => ageInMonths / 12;

  MetricEntry? get latest => entries.isEmpty ? null : entries.last;

  MetricEntry? get latestWithWeight {
    for (final entry in entries.reversed) {
      if (entry.weightKg != null) return entry;
    }
    return null;
  }

  MetricEntry? get latestWithHeight {
    for (final entry in entries.reversed) {
      if (entry.heightCm != null) return entry;
    }
    return null;
  }
}

class MetricEntry {
  const MetricEntry({
    required this.id,
    required this.profileId,
    required this.date,
    this.weightKg,
    this.heightCm,
  });

  final int id;
  final int profileId;
  final DateTime date;
  final double? weightKg;
  final double? heightCm;

  double? get bmi {
    if (weightKg == null || heightCm == null || heightCm == 0) return null;
    return weightKg! / pow(heightCm! / 100, 2);
  }
}

class CreateProfileInput {
  const CreateProfileInput({
    required this.name,
    required this.purpose,
    required this.birthDate,
    required this.weightUnit,
    required this.heightUnit,
    this.initialWeight,
    this.initialHeight,
  });

  final String name;
  final String purpose;
  final DateTime birthDate;
  final WeightUnit weightUnit;
  final HeightUnit heightUnit;
  final double? initialWeight;
  final double? initialHeight;
}

class ProfileRepository {
  ProfileRepository._();

  static final ProfileRepository instance = ProfileRepository._();
  static const _selectedProfileKey = 'selected_profile_id';

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'growth_tracker.db');

    _db = await openDatabase(
      fullPath,
      version: 2,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS entries');
        await db.execute('DROP TABLE IF EXISTS profiles');
        await _createTables(db);
      },
    );
  }

  Future<void> _createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE profiles(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        purpose TEXT NOT NULL,
        birth_date TEXT NOT NULL,
        weight_unit TEXT NOT NULL,
        height_unit TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        weight_kg REAL,
        height_cm REAL,
        FOREIGN KEY(profile_id) REFERENCES profiles(id) ON DELETE CASCADE
      );
    ''');
  }

  Future<List<GrowthProfile>> fetchProfiles() async {
    final db = _db!;
    final profilesRaw = await db.query('profiles', orderBy: 'created_at ASC');
    final entriesRaw = await db.query('entries', orderBy: 'date ASC');

    final groupedEntries = <int, List<MetricEntry>>{};
    for (final row in entriesRaw) {
      final entry = MetricEntry(
        id: row['id'] as int,
        profileId: row['profile_id'] as int,
        date: DateTime.parse(row['date'] as String),
        weightKg: (row['weight_kg'] as num?)?.toDouble(),
        heightCm: (row['height_cm'] as num?)?.toDouble(),
      );
      groupedEntries.putIfAbsent(entry.profileId, () => []).add(entry);
    }

    return profilesRaw
        .map(
          (row) => GrowthProfile(
            id: row['id'] as int,
            name: row['name'] as String,
            purpose: row['purpose'] as String,
            birthDate: DateTime.parse(row['birth_date'] as String),
            weightUnit: (row['weight_unit'] as String) == 'lbs' ? WeightUnit.lbs : WeightUnit.kg,
            heightUnit: (row['height_unit'] as String) == 'ft' ? HeightUnit.ft : HeightUnit.cm,
            entries: groupedEntries[row['id'] as int] ?? [],
          ),
        )
        .toList();
  }

  Future<void> createProfile(CreateProfileInput input) async {
    final db = _db!;
    await db.transaction((txn) async {
      final profileId = await txn.insert('profiles', {
        'name': input.name,
        'purpose': input.purpose,
        'birth_date': input.birthDate.toIso8601String(),
        'weight_unit': input.weightUnit.label,
        'height_unit': input.heightUnit.label,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (input.initialWeight != null || input.initialHeight != null) {
        await txn.insert('entries', {
          'profile_id': profileId,
          'date': DateTime.now().toIso8601String(),
          'weight_kg': input.initialWeight == null
              ? null
              : UnitConverter.fromDisplayWeight(input.initialWeight!, input.weightUnit),
          'height_cm': input.initialHeight == null
              ? null
              : UnitConverter.fromDisplayHeight(input.initialHeight!, input.heightUnit),
        });
      }

      await setSelectedProfileId(profileId);
    });
  }

  Future<void> addEntry({
    required int profileId,
    required DateTime date,
    required double? weightKg,
    required double? heightCm,
  }) async {
    await _db!.insert('entries', {
      'profile_id': profileId,
      'date': date.toIso8601String(),
      'weight_kg': weightKg,
      'height_cm': heightCm,
    });
  }

  Future<void> updateProfile({
    required int profileId,
    required String name,
    required String purpose,
    required DateTime birthDate,
    required WeightUnit weightUnit,
    required HeightUnit heightUnit,
  }) async {
    await _db!.update(
      'profiles',
      {
        'name': name,
        'purpose': purpose,
        'birth_date': birthDate.toIso8601String(),
        'weight_unit': weightUnit.label,
        'height_unit': heightUnit.label,
      },
      where: 'id = ?',
      whereArgs: [profileId],
    );
  }

  Future<void> updateEntry({
    required int entryId,
    required DateTime date,
    required double? weightKg,
    required double? heightCm,
  }) async {
    await _db!.update(
      'entries',
      {
        'date': date.toIso8601String(),
        'weight_kg': weightKg,
        'height_cm': heightCm,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  Future<int?> getSelectedProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_selectedProfileKey);
  }

  Future<void> setSelectedProfileId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_selectedProfileKey, id);
  }
}

class RegistrationScreen extends StatelessWidget {
  const RegistrationScreen({super.key, required this.onCreateProfile});

  final Future<void> Function(CreateProfileInput input) onCreateProfile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create your first profile')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CreateProfileForm(onSubmit: onCreateProfile),
            ),
          ),
        ),
      ),
    );
  }
}

class TrackerDashboard extends StatelessWidget {
  const TrackerDashboard({
    super.key,
    required this.profiles,
    required this.selectedProfileId,
    required this.onSelectProfile,
    required this.onDataChanged,
    required this.onCreateProfile,
  });

  final List<GrowthProfile> profiles;
  final int? selectedProfileId;
  final ValueChanged<int> onSelectProfile;
  final Future<void> Function() onDataChanged;
  final Future<void> Function(CreateProfileInput input) onCreateProfile;

  GrowthProfile get selectedProfile {
    if (selectedProfileId == null) return profiles.first;
    return profiles.firstWhere(
      (profile) => profile.id == selectedProfileId,
      orElse: () => profiles.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = selectedProfile;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile.name),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Profiles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final item in profiles)
                      ListTile(
                        title: Text(item.name),
                        subtitle: Text(item.purpose),
                        selected: item.id == profile.id,
                        onTap: () {
                          onSelectProfile(item.id);
                          Navigator.pop(context);
                        },
                        trailing: IconButton(
                          tooltip: 'Edit profile',
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            await showDialog<void>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Edit profile'),
                                content: SizedBox(
                                  width: 540,
                                  child: EditProfileForm(
                                    profile: item,
                                    onSubmit: (input) async {
                                      await ProfileRepository.instance.updateProfile(
                                        profileId: item.id,
                                        name: input.name,
                                        purpose: input.purpose,
                                        birthDate: input.birthDate,
                                        weightUnit: input.weightUnit,
                                        heightUnit: input.heightUnit,
                                      );
                                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                                      await onDataChanged();
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Create profile'),
                        content: SizedBox(
                          width: 540,
                          child: CreateProfileForm(
                            onSubmit: (input) async {
                              await onCreateProfile(input);
                              if (dialogContext.mounted) Navigator.pop(dialogContext);
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add profile'),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await showModalBottomSheet<AddEntryInput>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => AddEntrySheet(profile: profile),
          );
          if (result != null) {
            await ProfileRepository.instance.addEntry(
              profileId: profile.id,
              date: result.date,
              weightKg: result.weight == null
                  ? null
                  : UnitConverter.fromDisplayWeight(result.weight!, profile.weightUnit),
              heightCm: result.height == null
                  ? null
                  : UnitConverter.fromDisplayHeight(result.height!, profile.heightUnit),
            );
            await onDataChanged();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add measurement'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ProfileOverviewCard(profile: profile),
          const SizedBox(height: 12),
          AgeBasedInsightCard(profile: profile),
          const SizedBox(height: 12),
          BabyGrowthSummaryCard(profile: profile),
          const SizedBox(height: 12),
          TrendCharts(profile: profile),
          const SizedBox(height: 12),
          EntriesTable(profile: profile, onDataChanged: onDataChanged),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class CreateProfileForm extends StatefulWidget {
  const CreateProfileForm({super.key, required this.onSubmit});

  final Future<void> Function(CreateProfileInput input) onSubmit;

  @override
  State<CreateProfileForm> createState() => _CreateProfileFormState();
}

class EditProfileForm extends StatefulWidget {
  const EditProfileForm({super.key, required this.profile, required this.onSubmit});

  final GrowthProfile profile;
  final Future<void> Function(CreateProfileInput input) onSubmit;

  @override
  State<EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends State<EditProfileForm> {
  static const _purposeOptions = _CreateProfileFormState._purposeOptions;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late DateTime _birthDate;
  late WeightUnit _weightUnit;
  late HeightUnit _heightUnit;
  late String _purpose;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _birthDate = widget.profile.birthDate;
    _weightUnit = widget.profile.weightUnit;
    _heightUnit = widget.profile.heightUnit;
    _purpose = widget.profile.purpose;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _required,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _purpose,
              decoration: const InputDecoration(labelText: 'Purpose'),
              items: _purposeOptions
                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _purpose = value);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Birth date'),
              subtitle: Text(DateFormat('MM/dd/yy').format(_birthDate)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  initialDate: _birthDate,
                );
                if (picked != null) setState(() => _birthDate = picked);
              },
            ),
            const SizedBox(height: 8),
            SegmentedButton<WeightUnit>(
              segments: const [
                ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
                ButtonSegment(value: WeightUnit.lbs, label: Text('lbs')),
              ],
              selected: {_weightUnit},
              onSelectionChanged: (values) => setState(() => _weightUnit = values.first),
            ),
            const SizedBox(height: 8),
            SegmentedButton<HeightUnit>(
              segments: const [
                ButtonSegment(value: HeightUnit.cm, label: Text('cm')),
                ButtonSegment(value: HeightUnit.ft, label: Text('ft')),
              ],
              selected: {_heightUnit},
              onSelectionChanged: (values) => setState(() => _heightUnit = values.first),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      setState(() => _saving = true);
                      await widget.onSubmit(
                        CreateProfileInput(
                          name: _nameController.text.trim(),
                          purpose: _purpose,
                          birthDate: _birthDate,
                          weightUnit: _weightUnit,
                          heightUnit: _heightUnit,
                        ),
                      );
                      if (mounted) setState(() => _saving = false);
                    },
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Saving...' : 'Save profile changes'),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }
}

class _CreateProfileFormState extends State<CreateProfileForm> {
  static const _purposeOptions = [
    'Baby growth and development tracking',
    'Postpartum recovery progress',
    'Father/Mother weight loss journey',
    'General fitness and body composition monitoring',
    'Teen growth and sports conditioning',
    'Senior wellness and mobility monitoring',
    'Medical follow-up (as advised by clinician)',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  DateTime _birthDate = DateTime.now();
  WeightUnit _weightUnit = WeightUnit.kg;
  HeightUnit _heightUnit = HeightUnit.cm;
  String _purpose = _purposeOptions.first;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _required,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _purpose,
              decoration: const InputDecoration(labelText: 'Purpose'),
              items: _purposeOptions
                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _purpose = value);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Birth date'),
              subtitle: Text(DateFormat('MM/dd/yy').format(_birthDate)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  initialDate: _birthDate,
                );
                if (picked != null) setState(() => _birthDate = picked);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<WeightUnit>(
                    segments: const [
                      ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
                      ButtonSegment(value: WeightUnit.lbs, label: Text('lbs')),
                    ],
                    selected: {_weightUnit},
                    onSelectionChanged: (values) => setState(() => _weightUnit = values.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Initial weight (${_weightUnit.label}) • optional'),
              validator: _optionalPositive,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<HeightUnit>(
                    segments: const [
                      ButtonSegment(value: HeightUnit.cm, label: Text('cm')),
                      ButtonSegment(value: HeightUnit.ft, label: Text('ft')),
                    ],
                    selected: {_heightUnit},
                    onSelectionChanged: (values) => setState(() => _heightUnit = values.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Initial height (${_heightUnit.label}) • optional'),
              validator: _optionalPositive,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      setState(() => _saving = true);
                      await widget.onSubmit(
                        CreateProfileInput(
                          name: _nameController.text.trim(),
                          purpose: _purpose,
                          birthDate: _birthDate,
                          weightUnit: _weightUnit,
                          heightUnit: _heightUnit,
                          initialWeight: _parseOptional(_weightController.text),
                          initialHeight: _parseOptional(_heightController.text),
                        ),
                      );
                      if (mounted) setState(() => _saving = false);
                    },
              icon: _saving
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Save profile'),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  String? _optionalPositive(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) return 'Enter a positive value';
    return null;
  }

  double? _parseOptional(String value) {
    if (value.trim().isEmpty) return null;
    return double.parse(value.trim());
  }
}

class ProfileOverviewCard extends StatelessWidget {
  const ProfileOverviewCard({super.key, required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final latestWeight = profile.latestWithWeight?.weightKg;
    final latestHeight = profile.latestWithHeight?.heightCm;
    final latestBmi = profile.latest?.bmi;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile.name, style: Theme.of(context).textTheme.titleLarge),
            Text('Purpose: ${profile.purpose}'),
            Text('Birth date: ${DateFormat('MM/dd/yy').format(profile.birthDate)}'),
            Text('Age: ${profile.ageInYears.toStringAsFixed(2)} years'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (latestWeight != null)
                  _MetricTile(
                    label: 'Weight',
                    value:
                        '${UnitConverter.toDisplayWeight(latestWeight, profile.weightUnit).toStringAsFixed(1)} ${profile.weightUnit.label}',
                  ),
                if (latestHeight != null)
                  _MetricTile(
                    label: 'Height',
                    value:
                        '${UnitConverter.toDisplayHeight(latestHeight, profile.heightUnit).toStringAsFixed(1)} ${profile.heightUnit.label}',
                  ),
                if (latestBmi != null) _MetricTile(label: 'BMI', value: latestBmi.toStringAsFixed(1)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class AgeBasedInsightCard extends StatelessWidget {
  const AgeBasedInsightCard({super.key, required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final ageInYears = profile.ageInYears;
    final latest = profile.latest;

    final text = ageInYears < 1
        ? 'Baby development mode: focus on consistent height/weight progression over time and percentile-like trends instead of adult BMI targets.'
        : latest?.bmi == null
            ? 'Add both weight and height in at least one entry to compute BMI and richer insights.'
            : 'Current BMI is ${latest!.bmi!.toStringAsFixed(1)}. Keep gradual and consistent progress.';

    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.child_care),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class BabyGrowthSummaryCard extends StatelessWidget {
  const BabyGrowthSummaryCard({super.key, required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final reference = BabyGrowthReference.closestForMonths(profile.ageInMonths);
    if (reference == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Baby growth summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Age ${profile.ageInMonths} months (reference month: ${reference.month})'),
            Text(
              'Avg weight: ${UnitConverter.toDisplayWeight(reference.averageWeightKg, profile.weightUnit).toStringAsFixed(1)} ${profile.weightUnit.label}',
            ),
            Text(
              'Normal weight range: ${UnitConverter.toDisplayWeight(reference.minWeightKg, profile.weightUnit).toStringAsFixed(1)} - ${UnitConverter.toDisplayWeight(reference.maxWeightKg, profile.weightUnit).toStringAsFixed(1)} ${profile.weightUnit.label}',
            ),
            Text(
              'Avg height: ${UnitConverter.toDisplayHeight(reference.averageHeightCm, profile.heightUnit).toStringAsFixed(1)} ${profile.heightUnit.label}',
            ),
            Text(
              'Normal height range: ${UnitConverter.toDisplayHeight(reference.minHeightCm, profile.heightUnit).toStringAsFixed(1)} - ${UnitConverter.toDisplayHeight(reference.maxHeightCm, profile.heightUnit).toStringAsFixed(1)} ${profile.heightUnit.label}',
            ),
          ],
        ),
      ),
    );
  }
}

class TrendCharts extends StatelessWidget {
  const TrendCharts({super.key, required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final weightPoints = <MetricEntry>[];
    final heightPoints = <MetricEntry>[];
    for (final entry in profile.entries) {
      if (entry.weightKg != null) weightPoints.add(entry);
      if (entry.heightCm != null) heightPoints.add(entry);
    }

    return Column(
      children: [
        if (weightPoints.length >= 2) _WeightChartCard(profile: profile, entries: weightPoints),
        if (weightPoints.length >= 2 && heightPoints.length >= 2) const SizedBox(height: 12),
        if (heightPoints.length >= 2) _HeightChartCard(profile: profile, entries: heightPoints),
        if (weightPoints.length < 2 && heightPoints.length < 2)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Add at least 2 weight or 2 height entries to view charts.'),
            ),
          ),
      ],
    );
  }
}

class _WeightChartCard extends StatelessWidget {
  const _WeightChartCard({required this.profile, required this.entries});

  final GrowthProfile profile;
  final List<MetricEntry> entries;

  @override
  Widget build(BuildContext context) {
    final values = entries.map((e) => UnitConverter.toDisplayWeight(e.weightKg!, profile.weightUnit)).toList();
    final minValue = values.reduce(min);
    final maxValue = values.reduce(max);
    final midValue = (minValue + maxValue) / 2;
    final chartWidth = max(640.0, entries.length * 90.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weight Trend (${profile.weightUnit.label})', style: Theme.of(context).textTheme.titleMedium),
            Text('Min: ${minValue.toStringAsFixed(1)}  Mid: ${midValue.toStringAsFixed(1)}  Max: ${maxValue.toStringAsFixed(1)}'),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 260,
                child: LineChart(
                  LineChartData(
                    minY: minValue - 1,
                    maxY: maxValue + 1,
                    gridData: const FlGridData(show: true),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (value, _) {
                            final index = value.toInt();
                            if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                            return Text(DateFormat('MM/dd/yy').format(entries[index].date));
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        barWidth: 3,
                        color: Theme.of(context).colorScheme.primary,
                        spots: [
                          for (var i = 0; i < entries.length; i++)
                            FlSpot(i.toDouble(), UnitConverter.toDisplayWeight(entries[i].weightKg!, profile.weightUnit)),
                        ],
                        dotData: const FlDotData(show: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeightChartCard extends StatelessWidget {
  const _HeightChartCard({required this.profile, required this.entries});

  final GrowthProfile profile;
  final List<MetricEntry> entries;

  @override
  Widget build(BuildContext context) {
    final values = entries.map((e) => UnitConverter.toDisplayHeight(e.heightCm!, profile.heightUnit)).toList();
    final minValue = values.reduce(min);
    final maxValue = values.reduce(max);
    final midValue = (minValue + maxValue) / 2;
    final chartWidth = max(640.0, entries.length * 90.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Height Trend (${profile.heightUnit.label})', style: Theme.of(context).textTheme.titleMedium),
            Text('Min: ${minValue.toStringAsFixed(1)}  Mid: ${midValue.toStringAsFixed(1)}  Max: ${maxValue.toStringAsFixed(1)}'),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 260,
                child: BarChart(
                  BarChartData(
                    gridData: const FlGridData(show: true),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, _) {
                            final index = value.toInt();
                            if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                            return Text(DateFormat('MM/dd/yy').format(entries[index].date));
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < entries.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: UnitConverter.toDisplayHeight(entries[i].heightCm!, profile.heightUnit),
                              width: 16,
                              borderRadius: BorderRadius.circular(4),
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EntriesTable extends StatelessWidget {
  const EntriesTable({super.key, required this.profile, required this.onDataChanged});

  final GrowthProfile profile;
  final Future<void> Function() onDataChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = [...profile.entries]..sort((a, b) => b.date.compareTo(a.date));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Date')),
              DataColumn(label: Text('Weight (${profile.weightUnit.label})')),
              DataColumn(label: Text('Height (${profile.heightUnit.label})')),
              const DataColumn(label: Text('BMI')),
              const DataColumn(label: Text('Status')),
              const DataColumn(label: Text('Edit')),
            ],
            rows: [
              for (final entry in sorted)
                DataRow(
                  onSelectChanged: (_) => _showReasoning(context, entry),
                  cells: [
                    DataCell(Text(DateFormat('MM/dd/yy').format(entry.date))),
                    DataCell(
                      Text(
                        entry.weightKg == null
                            ? '-'
                            : UnitConverter.toDisplayWeight(entry.weightKg!, profile.weightUnit).toStringAsFixed(1),
                      ),
                    ),
                    DataCell(
                      Text(
                        entry.heightCm == null
                            ? '-'
                            : UnitConverter.toDisplayHeight(entry.heightCm!, profile.heightUnit).toStringAsFixed(1),
                      ),
                    ),
                    DataCell(Text(entry.bmi == null ? '-' : entry.bmi!.toStringAsFixed(1))),
                    DataCell(_EntryStatusPill(profile: profile, entry: entry)),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit entry',
                        onPressed: () async {
                          final edited = await showModalBottomSheet<AddEntryInput>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => AddEntrySheet(
                              profile: profile,
                              existingEntry: entry,
                            ),
                          );
                          if (edited == null) return;
                          await ProfileRepository.instance.updateEntry(
                            entryId: entry.id,
                            date: edited.date,
                            weightKg: edited.weight == null
                                ? null
                                : UnitConverter.fromDisplayWeight(edited.weight!, profile.weightUnit),
                            heightCm: edited.height == null
                                ? null
                                : UnitConverter.fromDisplayHeight(edited.height!, profile.heightUnit),
                          );
                          await onDataChanged();
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReasoning(BuildContext context, MetricEntry entry) {
    final status = BabyGrowthReference.evaluateStatus(
      birthDate: profile.birthDate,
      entry: entry,
    );
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Entry range explanation'),
        content: Text(status.reason),
      ),
    );
  }
}

class _EntryStatusPill extends StatelessWidget {
  const _EntryStatusPill({required this.profile, required this.entry});

  final GrowthProfile profile;
  final MetricEntry entry;

  @override
  Widget build(BuildContext context) {
    final status = BabyGrowthReference.evaluateStatus(
      birthDate: profile.birthDate,
      entry: entry,
    );
    final color = switch (status.level) {
      GrowthStatusLevel.inRange => Colors.green,
      GrowthStatusLevel.caution => Colors.orange,
      GrowthStatusLevel.outOfRange => Colors.red,
      GrowthStatusLevel.info => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: color, size: 10),
          const SizedBox(width: 6),
          Text(status.label),
        ],
      ),
    );
  }
}

enum GrowthStatusLevel { inRange, caution, outOfRange, info }

class GrowthStatusResult {
  const GrowthStatusResult({
    required this.level,
    required this.label,
    required this.reason,
  });

  final GrowthStatusLevel level;
  final String label;
  final String reason;
}

class BabyGrowthReference {
  const BabyGrowthReference({
    required this.month,
    required this.minWeightKg,
    required this.averageWeightKg,
    required this.maxWeightKg,
    required this.minHeightCm,
    required this.averageHeightCm,
    required this.maxHeightCm,
  });

  final int month;
  final double minWeightKg;
  final double averageWeightKg;
  final double maxWeightKg;
  final double minHeightCm;
  final double averageHeightCm;
  final double maxHeightCm;

  static const _table = [
    BabyGrowthReference(month: 0, minWeightKg: 2.5, averageWeightKg: 3.4, maxWeightKg: 4.4, minHeightCm: 46, averageHeightCm: 50, maxHeightCm: 54),
    BabyGrowthReference(month: 3, minWeightKg: 4.8, averageWeightKg: 6.2, maxWeightKg: 8.0, minHeightCm: 56, averageHeightCm: 60, maxHeightCm: 65),
    BabyGrowthReference(month: 6, minWeightKg: 6.0, averageWeightKg: 7.9, maxWeightKg: 10.2, minHeightCm: 63, averageHeightCm: 67, maxHeightCm: 72),
    BabyGrowthReference(month: 9, minWeightKg: 6.8, averageWeightKg: 8.9, maxWeightKg: 11.4, minHeightCm: 67, averageHeightCm: 72, maxHeightCm: 77),
    BabyGrowthReference(month: 12, minWeightKg: 7.3, averageWeightKg: 9.6, maxWeightKg: 12.2, minHeightCm: 71, averageHeightCm: 76, maxHeightCm: 81),
    BabyGrowthReference(month: 18, minWeightKg: 8.1, averageWeightKg: 10.9, maxWeightKg: 13.9, minHeightCm: 76, averageHeightCm: 82, maxHeightCm: 88),
    BabyGrowthReference(month: 24, minWeightKg: 9.0, averageWeightKg: 12.2, maxWeightKg: 15.4, minHeightCm: 81, averageHeightCm: 88, maxHeightCm: 94),
  ];

  static BabyGrowthReference? closestForMonths(int ageMonths) {
    if (ageMonths < 0 || ageMonths > 24) return null;
    BabyGrowthReference closest = _table.first;
    for (final item in _table) {
      if ((item.month - ageMonths).abs() < (closest.month - ageMonths).abs()) {
        closest = item;
      }
    }
    return closest;
  }

  static GrowthStatusResult evaluateStatus({
    required DateTime birthDate,
    required MetricEntry entry,
  }) {
    final ageMonths = max(
      0,
      (entry.date.year - birthDate.year) * 12 + (entry.date.month - birthDate.month),
    );
    final reference = closestForMonths(ageMonths);
    if (reference == null) {
      return const GrowthStatusResult(
        level: GrowthStatusLevel.info,
        label: 'No ref',
        reason: 'No baby reference is available for this age (supported: 0-24 months).',
      );
    }
    if (entry.weightKg == null && entry.heightCm == null) {
      return const GrowthStatusResult(
        level: GrowthStatusLevel.info,
        label: 'Missing data',
        reason: 'The entry has no weight or height.',
      );
    }

    bool anyOut = false;
    bool anyCaution = false;
    final messages = <String>[];

    if (entry.weightKg != null) {
      if (entry.weightKg! < reference.minWeightKg || entry.weightKg! > reference.maxWeightKg) {
        anyOut = true;
        messages.add(
          'Weight ${entry.weightKg!.toStringAsFixed(1)}kg is outside ${reference.minWeightKg.toStringAsFixed(1)}-${reference.maxWeightKg.toStringAsFixed(1)}kg.',
        );
      } else {
        final edge = (reference.maxWeightKg - reference.minWeightKg) * 0.15;
        if ((entry.weightKg! - reference.minWeightKg) < edge || (reference.maxWeightKg - entry.weightKg!) < edge) {
          anyCaution = true;
          messages.add('Weight is within range but close to the boundary.');
        } else {
          messages.add('Weight is in the expected range.');
        }
      }
    }

    if (entry.heightCm != null) {
      if (entry.heightCm! < reference.minHeightCm || entry.heightCm! > reference.maxHeightCm) {
        anyOut = true;
        messages.add(
          'Height ${entry.heightCm!.toStringAsFixed(1)}cm is outside ${reference.minHeightCm.toStringAsFixed(1)}-${reference.maxHeightCm.toStringAsFixed(1)}cm.',
        );
      } else {
        final edge = (reference.maxHeightCm - reference.minHeightCm) * 0.15;
        if ((entry.heightCm! - reference.minHeightCm) < edge || (reference.maxHeightCm - entry.heightCm!) < edge) {
          anyCaution = true;
          messages.add('Height is within range but close to the boundary.');
        } else {
          messages.add('Height is in the expected range.');
        }
      }
    }

    if (anyOut) {
      return GrowthStatusResult(
        level: GrowthStatusLevel.outOfRange,
        label: 'Out of range',
        reason: 'Reference month: ${reference.month}. ${messages.join(' ')}',
      );
    }
    if (anyCaution) {
      return GrowthStatusResult(
        level: GrowthStatusLevel.caution,
        label: 'Watch',
        reason: 'Reference month: ${reference.month}. ${messages.join(' ')}',
      );
    }
    return GrowthStatusResult(
      level: GrowthStatusLevel.inRange,
      label: 'Normal',
      reason: 'Reference month: ${reference.month}. ${messages.join(' ')}',
    );
  }
}

class AddEntryInput {
  const AddEntryInput({required this.date, this.weight, this.height});

  final DateTime date;
  final double? weight;
  final double? height;
}

class AddEntrySheet extends StatefulWidget {
  const AddEntrySheet({super.key, required this.profile, this.existingEntry});

  final GrowthProfile profile;
  final MetricEntry? existingEntry;

  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.existingEntry?.date ?? DateTime.now();
    _weightController = TextEditingController(
      text: widget.existingEntry?.weightKg == null
          ? ''
          : UnitConverter.toDisplayWeight(widget.existingEntry!.weightKg!, widget.profile.weightUnit)
                .toStringAsFixed(1),
    );
    _heightController = TextEditingController(
      text: widget.existingEntry?.heightCm == null
          ? ''
          : UnitConverter.toDisplayHeight(widget.existingEntry!.heightCm!, widget.profile.heightUnit)
                .toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.existingEntry == null ? 'Add' : 'Edit'} measurement for ${widget.profile.name}'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Weight (${widget.profile.weightUnit.label}) • optional'),
              validator: _optionalPositive,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Height (${widget.profile.heightUnit.label}) • optional'),
              validator: _optionalPositive,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Measurement date'),
              subtitle: Text(DateFormat('MM/dd/yy').format(_selectedDate)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  initialDate: _selectedDate,
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),
            FilledButton.icon(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                final weight = _parseOptional(_weightController.text);
                final height = _parseOptional(_heightController.text);
                if (weight == null && height == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Provide at least weight or height.')),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  AddEntryInput(date: _selectedDate, weight: weight, height: height),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Save entry'),
            ),
          ],
        ),
      ),
    );
  }

  String? _optionalPositive(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) return 'Enter a positive value';
    return null;
  }

  double? _parseOptional(String value) {
    if (value.trim().isEmpty) return null;
    return double.parse(value.trim());
  }
}
