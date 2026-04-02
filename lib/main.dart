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
      title: 'Family Health',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D84C6),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF1D84C6),
          secondary: const Color(0xFF4CAF50),
          tertiary: const Color(0xFFFF9800),
          surface: const Color(0xFFF7FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F7FB),
      ),
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

class AgeDisplayFormatter {
  static String yearsWithTwoDecimals(DateTime birthDate, {DateTime? asOf}) {
    final date = asOf ?? DateTime.now();
    final months = _monthsBetween(birthDate, date);
    return (months / 12).toStringAsFixed(2);
  }

  static String babyMonthsAndDays(DateTime birthDate, {DateTime? asOf}) {
    final date = asOf ?? DateTime.now();
    final months = _monthsBetween(birthDate, date);
    final monthAnchor = DateTime(birthDate.year, birthDate.month + months, birthDate.day);
    final days = date.difference(monthAnchor).inDays.clamp(0, 31);
    final monthLabel = months == 1 ? 'month' : 'months';
    final dayLabel = days == 1 ? 'day' : 'days';
    return '$months $monthLabel and $days $dayLabel';
  }

  static int monthsBetween(DateTime from, DateTime to) => _monthsBetween(from, to);

  static int _monthsBetween(DateTime from, DateTime to) {
    if (to.isBefore(from)) return 0;
    var months = (to.year - from.year) * 12 + to.month - from.month;
    if (to.day < from.day) months -= 1;
    return months.clamp(0, 1000);
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
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(8),
          child: _LogoBadge(size: 36),
        ),
        title: const Text('Create your first profile'),
      ),
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
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Open profiles',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            const _LogoBadge(size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(profile.name)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Edit profile',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Edit profile'),
                  content: SizedBox(
                    width: 540,
                    child: EditProfileForm(
                      profile: profile,
                      onSubmit: (input) async {
                        await ProfileRepository.instance.updateProfile(
                          profileId: profile.id,
                          name: input.name,
                          purpose: input.purpose,
                          birthDate: input.birthDate,
                          weightUnit: input.weightUnit,
                          heightUnit: input.heightUnit,
                        );
                        await onDataChanged();
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ],
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

class _CreateProfileFormState extends State<CreateProfileForm> {
  static const purposeOptions = [
    'Baby growth tracking',
    'Postpartum recovery',
    'Weight loss journey',
    'Fitness tracking',
    'Teen growth',
    'Senior wellness',
    'Clinical follow-up',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  DateTime _birthDate = DateTime.now();
  WeightUnit _weightUnit = WeightUnit.kg;
  HeightUnit _heightUnit = HeightUnit.cm;
  String _purpose = purposeOptions.first;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: _LogoBadge(size: 72),
            ),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _required,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _purpose,
              decoration: const InputDecoration(labelText: 'Purpose'),
              items: purposeOptions
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
            Text(
              profile.ageInYears < 1
                  ? 'Age: ${AgeDisplayFormatter.babyMonthsAndDays(profile.birthDate)}'
                  : 'Age: ${AgeDisplayFormatter.yearsWithTwoDecimals(profile.birthDate)} years',
            ),
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
    final babySummary = BabyGrowthReference.summaryFor(profile);

    final text = ageInYears < 1
        ? 'Baby development mode: compare growth against reference trajectory lines instead of adult BMI targets.'
        : latest?.bmi == null
            ? 'Add both weight and height in at least one entry to compute BMI and richer insights.'
            : 'Current BMI is ${latest!.bmi!.toStringAsFixed(1)}. Keep gradual and consistent progress.';

    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.child_care),
                const SizedBox(width: 8),
                Expanded(child: Text(text)),
              ],
            ),
            if (babySummary != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text(
                'Baby growth summary (${babySummary.ageLabel})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Average weight: ${_formatNumber(babySummary.avgWeightKg)} kg '
                '(${_formatNumber(UnitConverter.toDisplayWeight(babySummary.avgWeightKg, profile.weightUnit))} ${profile.weightUnit.label})',
              ),
              Text(
                'Average height: ${_formatNumber(babySummary.avgHeightCm)} cm '
                '(${_formatNumber(UnitConverter.toDisplayHeight(babySummary.avgHeightCm, profile.heightUnit))} ${profile.heightUnit.label})',
              ),
              Text(
                'Normal range: weight ${_formatRangeKg(babySummary.minWeightKg, babySummary.maxWeightKg, profile.weightUnit)} '
                'and height ${_formatRangeCm(babySummary.minHeightCm, babySummary.maxHeightCm, profile.heightUnit)}.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRangeKg(double low, double high, WeightUnit unit) {
    final lowDisplay = UnitConverter.toDisplayWeight(low, unit);
    final highDisplay = UnitConverter.toDisplayWeight(high, unit);
    return '${_formatNumber(lowDisplay)}-${_formatNumber(highDisplay)} ${unit.label}';
  }

  String _formatRangeCm(double low, double high, HeightUnit unit) {
    final lowDisplay = UnitConverter.toDisplayHeight(low, unit);
    final highDisplay = UnitConverter.toDisplayHeight(high, unit);
    return '${_formatNumber(lowDisplay)}-${_formatNumber(highDisplay)} ${unit.label}';
  }

  String _formatNumber(double value) => value.toStringAsFixed(1);
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
    final isBabyProfile = profile.ageInYears < 2;
    final values = entries.map((e) => UnitConverter.toDisplayHeight(e.heightCm!, profile.heightUnit)).toList();
    final guidanceTarget = _guidanceLine(entries, profile, factor: 1.0);
    final guidanceLow = _guidanceLine(entries, profile, factor: 0.93);
    final minValue = [...values, ...guidanceLow.map((e) => e.y)].reduce(min);
    final maxValue = [...values, ...guidanceTarget.map((e) => e.y)].reduce(max);
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
                        color: Theme.of(context).colorScheme.tertiary,
                        spots: [
                          for (var i = 0; i < entries.length; i++)
                            FlSpot(i.toDouble(), UnitConverter.toDisplayHeight(entries[i].heightCm!, profile.heightUnit)),
                        ],
                        dotData: const FlDotData(show: true),
                      ),
                      if (isBabyProfile)
                        LineChartBarData(
                          isCurved: true,
                          barWidth: 2,
                          color: Colors.green.shade700,
                          spots: guidanceTarget,
                          dotData: const FlDotData(show: false),
                          dashArray: const [7, 4],
                        ),
                      if (isBabyProfile)
                        LineChartBarData(
                          isCurved: true,
                          barWidth: 2,
                          color: Colors.red.shade700,
                          spots: guidanceLow,
                          dotData: const FlDotData(show: false),
                          dashArray: const [7, 4],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (isBabyProfile)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Green = expected trajectory, Red = lower-bound trajectory (guidance only, not a diagnosis).',
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _guidanceLine(List<MetricEntry> entries, GrowthProfile profile, {required double factor}) {
    final first = UnitConverter.toDisplayHeight(entries.first.heightCm!, profile.heightUnit);
    return [
      for (var i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), (first + i * 1.2) * factor),
    ];
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: const Image(
        image: AssetImage('assets/APP_ICON.png'),
        fit: BoxFit.cover,
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
            ],
            rows: [
              for (final entry in sorted)
                DataRow.byIndex(
                  index: entry.id,
                  color: MaterialStatePropertyAll(
                    BabyGrowthReference.colorForEntry(profile, entry).withOpacity(0.14),
                  ),
                  cells: [
                    DataCell(
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: BabyGrowthReference.colorForEntry(profile, entry),
                          ),
                          const SizedBox(width: 6),
                          Text(DateFormat('MM/dd/yy').format(entry.date)),
                        ],
                      ),
                      onTap: () => _showEntryExplanation(context, entry),
                    ),
                    DataCell(
                      Text(
                        entry.weightKg == null
                            ? '-'
                            : UnitConverter.toDisplayWeight(entry.weightKg!, profile.weightUnit).toStringAsFixed(1),
                      ),
                      onTap: () => _showEntryExplanation(context, entry),
                    ),
                    DataCell(
                      Text(
                        entry.heightCm == null
                            ? '-'
                            : UnitConverter.toDisplayHeight(entry.heightCm!, profile.heightUnit).toStringAsFixed(1),
                      ),
                      onTap: () => _showEntryExplanation(context, entry),
                    ),
                    DataCell(
                      Text(entry.bmi == null ? '-' : entry.bmi!.toStringAsFixed(1)),
                      onTap: () => _showEntryExplanation(context, entry),
                    ),
                  ],
                  onSelectChanged: (_) => _showEditEntrySheet(context, entry),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditEntrySheet(BuildContext context, MetricEntry entry) async {
    final result = await showModalBottomSheet<AddEntryInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddEntrySheet(profile: profile, initialEntry: entry),
    );
    if (result == null) return;
    await ProfileRepository.instance.updateEntry(
      entryId: entry.id,
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

  void _showEntryExplanation(BuildContext context, MetricEntry entry) {
    final explanation = BabyGrowthReference.explainEntry(profile, entry);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Explanation'),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
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
  const AddEntrySheet({super.key, required this.profile, this.initialEntry});

  final GrowthProfile profile;
  final MetricEntry? initialEntry;

  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEntry;
    _selectedDate = initial?.date ?? DateTime.now();
    if (initial?.weightKg != null) {
      _weightController.text =
          UnitConverter.toDisplayWeight(initial!.weightKg!, widget.profile.weightUnit).toStringAsFixed(1);
    }
    if (initial?.heightCm != null) {
      _heightController.text =
          UnitConverter.toDisplayHeight(initial!.heightCm!, widget.profile.heightUnit).toStringAsFixed(1);
    }
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
            Text('${widget.initialEntry == null ? 'Add' : 'Edit'} measurement for ${widget.profile.name}'),
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
              label: Text(widget.initialEntry == null ? 'Save entry' : 'Update entry'),
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

class EditProfileForm extends StatefulWidget {
  const EditProfileForm({super.key, required this.profile, required this.onSubmit});

  final GrowthProfile profile;
  final Future<void> Function(CreateProfileInput input) onSubmit;

  @override
  State<EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends State<EditProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String _purpose;
  late DateTime _birthDate;
  late WeightUnit _weightUnit;
  late HeightUnit _heightUnit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _purpose = widget.profile.purpose;
    _birthDate = widget.profile.birthDate;
    _weightUnit = widget.profile.weightUnit;
    _heightUnit = widget.profile.heightUnit;
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
              items: _CreateProfileFormState.purposeOptions
                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _purpose = value);
              },
            ),
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
                      if (mounted) {
                        setState(() => _saving = false);
                        Navigator.pop(context);
                      }
                    },
              icon: _saving
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Updating...' : 'Update profile'),
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

class BabyGrowthSnapshot {
  const BabyGrowthSnapshot({
    required this.minWeightKg,
    required this.avgWeightKg,
    required this.maxWeightKg,
    required this.minHeightCm,
    required this.avgHeightCm,
    required this.maxHeightCm,
    required this.ageLabel,
  });

  final double minWeightKg;
  final double avgWeightKg;
  final double maxWeightKg;
  final double minHeightCm;
  final double avgHeightCm;
  final double maxHeightCm;
  final String ageLabel;
}

class BabyGrowthReference {
  static const _snapshots = <int, BabyGrowthSnapshot>{
    0: BabyGrowthSnapshot(
      minWeightKg: 2.5,
      avgWeightKg: 3.3,
      maxWeightKg: 4.4,
      minHeightCm: 46.0,
      avgHeightCm: 50.0,
      maxHeightCm: 54.0,
      ageLabel: 'newborn',
    ),
    3: BabyGrowthSnapshot(
      minWeightKg: 4.8,
      avgWeightKg: 6.0,
      maxWeightKg: 7.6,
      minHeightCm: 57.0,
      avgHeightCm: 61.0,
      maxHeightCm: 65.0,
      ageLabel: '3 months',
    ),
    6: BabyGrowthSnapshot(
      minWeightKg: 6.4,
      avgWeightKg: 7.9,
      maxWeightKg: 9.8,
      minHeightCm: 63.0,
      avgHeightCm: 67.0,
      maxHeightCm: 71.0,
      ageLabel: '6 months',
    ),
    9: BabyGrowthSnapshot(
      minWeightKg: 7.2,
      avgWeightKg: 8.9,
      maxWeightKg: 11.1,
      minHeightCm: 67.0,
      avgHeightCm: 72.0,
      maxHeightCm: 76.0,
      ageLabel: '9 months',
    ),
    12: BabyGrowthSnapshot(
      minWeightKg: 7.8,
      avgWeightKg: 9.6,
      maxWeightKg: 12.0,
      minHeightCm: 71.0,
      avgHeightCm: 76.0,
      maxHeightCm: 81.0,
      ageLabel: '12 months',
    ),
    18: BabyGrowthSnapshot(
      minWeightKg: 8.8,
      avgWeightKg: 11.0,
      maxWeightKg: 13.8,
      minHeightCm: 76.0,
      avgHeightCm: 82.0,
      maxHeightCm: 88.0,
      ageLabel: '18 months',
    ),
    24: BabyGrowthSnapshot(
      minWeightKg: 9.7,
      avgWeightKg: 12.3,
      maxWeightKg: 15.5,
      minHeightCm: 81.0,
      avgHeightCm: 87.0,
      maxHeightCm: 93.0,
      ageLabel: '24 months',
    ),
  };

  static BabyGrowthSnapshot? summaryFor(GrowthProfile profile) {
    if (profile.ageInMonths > 24) return null;
    final nearestMonth = _snapshots.keys.reduce(
      (a, b) => (profile.ageInMonths - a).abs() <= (profile.ageInMonths - b).abs() ? a : b,
    );
    return _snapshots[nearestMonth];
  }

  static BabyGrowthSnapshot? _snapshotForDate(GrowthProfile profile, DateTime measuredDate) {
    final ageInMonths = AgeDisplayFormatter.monthsBetween(profile.birthDate, measuredDate);
    if (ageInMonths > 24) return null;
    final nearestMonth = _snapshots.keys.reduce(
      (a, b) => (ageInMonths - a).abs() <= (ageInMonths - b).abs() ? a : b,
    );
    return _snapshots[nearestMonth];
  }

  static Color colorForEntry(GrowthProfile profile, MetricEntry entry) {
    final snapshot = _snapshotForDate(profile, entry.date);
    if (snapshot == null) return Colors.blueGrey;

    final weight = entry.weightKg;
    final height = entry.heightCm;
    final hasWeight = weight != null;
    final hasHeight = height != null;
    if (!hasWeight && !hasHeight) return Colors.blueGrey;

    final outOfRangeWeight = hasWeight && (weight! < snapshot.minWeightKg || weight > snapshot.maxWeightKg);
    final outOfRangeHeight = hasHeight && (height! < snapshot.minHeightCm || height > snapshot.maxHeightCm);
    if (outOfRangeWeight || outOfRangeHeight) return Colors.red;
    return Colors.green;
  }

  static String explainEntry(GrowthProfile profile, MetricEntry entry) {
    final snapshot = _snapshotForDate(profile, entry.date);
    if (snapshot == null) {
      return 'This entry is shown as neutral because baby growth reference ranges are used through 24 months of age.';
    }

    final weight = entry.weightKg;
    final height = entry.heightCm;
    final details = <String>[];
    if (weight != null) {
      details.add(
        'Weight recorded: ${weight.toStringAsFixed(1)} kg. '
        'Typical range for this age band: ${snapshot.minWeightKg.toStringAsFixed(1)}-${snapshot.maxWeightKg.toStringAsFixed(1)} kg.',
      );
    }
    if (height != null) {
      details.add(
        'Length/height recorded: ${height.toStringAsFixed(1)} cm. '
        'Typical range for this age band: ${snapshot.minHeightCm.toStringAsFixed(1)}-${snapshot.maxHeightCm.toStringAsFixed(1)} cm.',
      );
    }

    final color = colorForEntry(profile, entry);
    final reason = color == Colors.red
        ? 'Marked red because at least one measured value is outside the expected range for age.'
        : color == Colors.green
            ? 'Marked green because the available measurements are within expected age-based ranges.'
            : 'Marked neutral because no measurements were recorded for this entry.';
    final measuredAge = AgeDisplayFormatter.babyMonthsAndDays(
      profile.birthDate,
      asOf: entry.date,
    );
    final detailText = details.isEmpty ? '' : '\n\n${details.join('\n')}';
    return '$reason$detailText\n\nReference age band: ${snapshot.ageLabel} (measured at $measuredAge).';
  }
}
