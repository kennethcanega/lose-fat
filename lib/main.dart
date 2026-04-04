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

enum ProfileGender { male, female }

extension WeightUnitX on WeightUnit {
  String get label => this == WeightUnit.kg ? 'kg' : 'lbs';
}

extension HeightUnitX on HeightUnit {
  String get label => this == HeightUnit.cm ? 'cm' : 'ft';
}

extension ProfileGenderX on ProfileGender {
  String get label => this == ProfileGender.male ? 'Male' : 'Female';
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
    required this.gender,
    required this.birthDate,
    required this.weightUnit,
    required this.heightUnit,
    required this.entries,
  });

  final int id;
  final String name;
  final String purpose;
  final ProfileGender gender;
  final DateTime birthDate;
  final WeightUnit weightUnit;
  final HeightUnit heightUnit;
  final List<MetricEntry> entries;

  int get ageInMonths {
    final now = DateTime.now();
    return AgeDisplayFormatter.monthsBetween(birthDate, now);
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
  static int wholeYears(DateTime birthDate, {DateTime? asOf}) {
    final date = asOf ?? DateTime.now();
    final months = _monthsBetween(birthDate, date);
    return months ~/ 12;
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

final DateFormat _birthDateFormatter = DateFormat('MMM. d, y');
final DateFormat _shortDateFormatter = DateFormat('MM/dd/yy');

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
    required this.gender,
    required this.birthDate,
    required this.weightUnit,
    required this.heightUnit,
    this.initialWeight,
    this.initialHeight,
  });

  final String name;
  final String purpose;
  final ProfileGender gender;
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
      version: 3,
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
        gender TEXT NOT NULL,
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
            gender: (row['gender'] as String) == 'female' ? ProfileGender.female : ProfileGender.male,
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
        'gender': input.gender.name,
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
    required ProfileGender gender,
    required DateTime birthDate,
    required WeightUnit weightUnit,
    required HeightUnit heightUnit,
  }) async {
    await _db!.update(
      'profiles',
      {
        'name': name,
        'purpose': purpose,
        'gender': gender.name,
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

  Future<void> deleteEntry(int entryId) async {
    await _db!.delete(
      'entries',
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  Future<void> deleteProfile(int profileId) async {
    await _db!.delete(
      'profiles',
      where: 'id = ?',
      whereArgs: [profileId],
    );
    final selectedProfileId = await getSelectedProfileId();
    if (selectedProfileId == profileId) {
      final remaining = await fetchProfiles();
      if (remaining.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_selectedProfileKey);
      } else {
        await setSelectedProfileId(remaining.first.id);
      }
    }
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
                          gender: input.gender,
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
          IconButton(
            tooltip: 'Delete profile',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete profile?'),
                  content: Text(
                    'This will permanently delete ${profile.name} and all of its entries.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await ProfileRepository.instance.deleteProfile(profile.id);
              await onDataChanged();
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
          TrendCharts(profile: profile, onDataChanged: onDataChanged),
          if (profile.ageInMonths <= 12) ...[
            const SizedBox(height: 12),
            BabyDevelopmentProgressCard(profile: profile),
          ],
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
    'Health Track',
    'Teen growth',
    'Senior wellness',
    'Clinical follow-up',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  DateTime? _birthDate;
  WeightUnit _weightUnit = WeightUnit.kg;
  HeightUnit _heightUnit = HeightUnit.cm;
  ProfileGender? _gender;
  String? _purpose;
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
              hint: const Text('Select purpose'),
              decoration: const InputDecoration(labelText: 'Purpose'),
              items: purposeOptions
                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _purpose = value);
              },
              validator: _required,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ProfileGender>(
              value: _gender,
              hint: const Text('Select gender'),
              decoration: const InputDecoration(labelText: 'Gender'),
              items: ProfileGender.values
                  .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                  .toList(),
              onChanged: (value) => setState(() => _gender = value),
              validator: (value) => value == null ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Birth date'),
              subtitle: Text(
                _birthDate == null ? 'Required' : _birthDateFormatter.format(_birthDate!),
              ),
              subtitleTextStyle: TextStyle(
                color: _birthDate == null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).textTheme.bodyMedium?.color,
              ),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  initialDate: _birthDate ?? DateTime.now(),
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
                      if (_birthDate == null || _purpose == null || _gender == null) {
                        setState(() {});
                        return;
                      }
                      setState(() => _saving = true);
                      await widget.onSubmit(
                        CreateProfileInput(
                          name: _nameController.text.trim(),
                          purpose: _purpose!,
                          gender: _gender!,
                          birthDate: _birthDate!,
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
    final isBabyProfile = profile.ageInYears < 2;
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
            Text('Birth date: ${_birthDateFormatter.format(profile.birthDate)}'),
            Text(
              profile.ageInYears < 1
                  ? 'Age: ${AgeDisplayFormatter.babyMonthsAndDays(profile.birthDate)}'
                  : 'Age: ${AgeDisplayFormatter.wholeYears(profile.birthDate)} years old',
            ),
            Text('Gender: ${profile.gender.label}'),
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
                if (!isBabyProfile && latestBmi != null) _MetricTile(label: 'BMI', value: latestBmi.toStringAsFixed(1)),
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

class AdultBmiInsight {
  const AdultBmiInsight({
    required this.label,
    required this.color,
    required this.weightToLoseKg,
  });

  final String label;
  final Color color;
  final double weightToLoseKg;
}

AdultBmiInsight classifyAdultBmi(MetricEntry entry, {required ProfileGender gender}) {
  final bmi = entry.bmi;
  if (bmi == null) {
    return const AdultBmiInsight(label: 'Not available', color: Colors.blueGrey, weightToLoseKg: 0);
  }

  final overweightThreshold = gender == ProfileGender.female ? 24.0 : 25.0;
  final obesityThreshold = gender == ProfileGender.female ? 29.0 : 30.0;

  if (bmi < 18.5) {
    return const AdultBmiInsight(label: 'Underweight', color: Colors.lightBlue, weightToLoseKg: 0);
  }
  if (bmi < overweightThreshold) {
    return const AdultBmiInsight(label: 'Normal', color: Colors.green, weightToLoseKg: 0);
  }
  if (bmi < obesityThreshold) {
    return AdultBmiInsight(
      label: 'Overweight',
      color: Colors.orange,
      weightToLoseKg: _weightToReachBmiUpperNormal(entry, gender: gender),
    );
  }
  return AdultBmiInsight(
    label: 'Obese',
    color: Colors.red,
    weightToLoseKg: _weightToReachBmiUpperNormal(entry, gender: gender),
  );
}

double _weightToReachBmiUpperNormal(MetricEntry entry, {required ProfileGender gender}) {
  if (entry.weightKg == null || entry.heightCm == null || entry.heightCm == 0) return 0;
  final heightM = entry.heightCm! / 100;
  final targetBmi = gender == ProfileGender.female ? 23.9 : 24.9;
  final targetWeight = targetBmi * heightM * heightM;
  return max(0, entry.weightKg! - targetWeight);
}

class AgeBasedInsightCard extends StatelessWidget {
  const AgeBasedInsightCard({super.key, required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final ageInYears = profile.ageInYears;
    final isBabyProfile = ageInYears < 2;
    final isAdultProfile = ageInYears >= 18;
    final latest = profile.latest;
    final babySummary = BabyGrowthReference.summaryFor(profile);
    final adultInsight =
        (isAdultProfile && latest?.bmi != null) ? classifyAdultBmi(latest!, gender: profile.gender) : null;
    final loseWeightDisplay = latest == null
        ? null
        : UnitConverter.toDisplayWeight(adultInsight?.weightToLoseKg ?? 0, profile.weightUnit);

    final text = ageInYears < 2
        ? 'Baby development mode: compare growth against reference trajectory lines instead of adult BMI targets.'
        : adultInsight != null
            ? 'Adult BMI: ${latest!.bmi!.toStringAsFixed(1)} • ${adultInsight.label}'
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
                Icon(isBabyProfile ? Icons.child_care : Icons.insights),
                const SizedBox(width: 8),
                Expanded(child: Text(text)),
              ],
            ),
            if (adultInsight != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    avatar: Icon(Icons.circle, size: 12, color: adultInsight.color),
                    label: Text(adultInsight.label),
                  ),
                  Chip(
                    label: Text(
                      loseWeightDisplay == null || loseWeightDisplay <= 0
                          ? 'Weight to lose: 0 ${profile.weightUnit.label}'
                          : 'Weight to lose: ${loseWeightDisplay.toStringAsFixed(1)} ${profile.weightUnit.label}',
                    ),
                  ),
                ],
              ),
            ],
            if (babySummary != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text(
                'Baby growth summary (${profile.gender.label}, ${babySummary.ageLabel})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SummaryStatCard(
                      title: 'Weight reference',
                      avgText:
                          '${_formatNumber(UnitConverter.toDisplayWeight(babySummary.avgWeightKg, profile.weightUnit))} ${profile.weightUnit.label}',
                      rangeText:
                          _formatRangeKg(babySummary.minWeightKg, babySummary.maxWeightKg, profile.weightUnit),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryStatCard(
                      title: 'Height reference',
                      avgText:
                          '${_formatNumber(UnitConverter.toDisplayHeight(babySummary.avgHeightCm, profile.heightUnit))} ${profile.heightUnit.label}',
                      rangeText:
                          _formatRangeCm(babySummary.minHeightCm, babySummary.maxHeightCm, profile.heightUnit),
                    ),
                  ),
                ],
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

class _SummaryStatCard extends StatelessWidget {
  const _SummaryStatCard({required this.title, required this.avgText, required this.rangeText});

  final String title;
  final String avgText;
  final String rangeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text('Average: $avgText'),
          Text('Range: $rangeText'),
        ],
      ),
    );
  }
}

class BabyDevelopmentProgressCard extends StatelessWidget {
  const BabyDevelopmentProgressCard({super.key, required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _BabyMonthlyProgressCarousel(profile: profile),
      ),
    );
  }
}

class _BabyMonthlyProgressCarousel extends StatefulWidget {
  const _BabyMonthlyProgressCarousel({required this.profile});

  final GrowthProfile profile;

  @override
  State<_BabyMonthlyProgressCarousel> createState() => _BabyMonthlyProgressCarouselState();
}

class _BabyMonthlyProgressCarouselState extends State<_BabyMonthlyProgressCarousel> {
  late final PageController _pageController;
  late int _selectedMonth;
  final Map<int, bool> _expandedByMonth = {};

  int get _currentMonth => widget.profile.ageInMonths.clamp(0, 12);
  bool get _isSelectedMonthExpanded => _expandedByMonth[_selectedMonth] ?? false;

  @override
  void initState() {
    super.initState();
    _selectedMonth = _currentMonth;
    _pageController = PageController(initialPage: _selectedMonth, viewportFraction: 0.9);
  }

  @override
  void didUpdateWidget(covariant _BabyMonthlyProgressCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id || oldWidget.profile.ageInMonths != widget.profile.ageInMonths) {
      _selectedMonth = _currentMonth;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_selectedMonth);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.timeline, size: 18),
            const SizedBox(width: 6),
            Text(
              'Monthly development progress (0-12 months)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Swipe left/right to explore expected development for each month (${widget.profile.gender.label} reference).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          height: _isSelectedMonthExpanded ? 360 : 220,
          child: PageView.builder(
            controller: _pageController,
            itemCount: 13,
            onPageChanged: (index) => setState(() => _selectedMonth = index),
            itemBuilder: (context, month) {
              final isCurrent = month == _currentMonth;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _BabyMonthCard(
                  profile: widget.profile,
                  month: month,
                  isCurrentMonth: isCurrent,
                  expanded: _expandedByMonth[month] ?? false,
                  onExpandedChanged: (value) {
                    setState(() => _expandedByMonth[month] = value);
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var month = 0; month <= 12; month++)
              GestureDetector(
                onTap: () {
                  _pageController.animateToPage(
                    month,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  );
                },
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: month == _selectedMonth
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Text(
                    '$month',
                    style: TextStyle(
                      fontSize: 10,
                      color: month == _selectedMonth ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BabyMonthCard extends StatefulWidget {
  const _BabyMonthCard({
    required this.profile,
    required this.month,
    required this.isCurrentMonth,
    required this.expanded,
    required this.onExpandedChanged,
  });

  final GrowthProfile profile;
  final int month;
  final bool isCurrentMonth;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<_BabyMonthCard> createState() => _BabyMonthCardState();
}

class _BabyMonthCardState extends State<_BabyMonthCard> {
  @override
  Widget build(BuildContext context) {
    final month = widget.month;
    final profile = widget.profile;
    final isCurrentMonth = widget.isCurrentMonth;
    final milestone = _milestoneForMonth(month);
    final minWeight = UnitConverter.toDisplayWeight(
      BabyGrowthReference.referenceWeightKgForAge(
        month.toDouble(),
        band: GrowthBand.lowerBound,
        gender: profile.gender,
      ),
      profile.weightUnit,
    );
    final avgWeight = UnitConverter.toDisplayWeight(
      BabyGrowthReference.referenceWeightKgForAge(
        month.toDouble(),
        band: GrowthBand.median,
        gender: profile.gender,
      ),
      profile.weightUnit,
    );
    final maxWeight = UnitConverter.toDisplayWeight(
      BabyGrowthReference.referenceWeightKgForAge(
        month.toDouble(),
        band: GrowthBand.upperBound,
        gender: profile.gender,
      ),
      profile.weightUnit,
    );
    final minHeight = UnitConverter.toDisplayHeight(
      BabyGrowthReference.referenceHeightCmForAge(
        month.toDouble(),
        band: GrowthBand.lowerBound,
        gender: profile.gender,
      ),
      profile.heightUnit,
    );
    final avgHeight = UnitConverter.toDisplayHeight(
      BabyGrowthReference.referenceHeightCmForAge(
        month.toDouble(),
        band: GrowthBand.median,
        gender: profile.gender,
      ),
      profile.heightUnit,
    );
    final maxHeight = UnitConverter.toDisplayHeight(
      BabyGrowthReference.referenceHeightCmForAge(
        month.toDouble(),
        band: GrowthBand.upperBound,
        gender: profile.gender,
      ),
      profile.heightUnit,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentMonth ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
          width: isCurrentMonth ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForMonth(month), size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Month $month', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (isCurrentMonth)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Current',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Weight: ${avgWeight.toStringAsFixed(1)} ${profile.weightUnit.label} '
            '(${minWeight.toStringAsFixed(1)}-${maxWeight.toStringAsFixed(1)})',
          ),
          const SizedBox(height: 4),
          Text(
            'Height: ${avgHeight.toStringAsFixed(1)} ${profile.heightUnit.label} '
            '(${minHeight.toStringAsFixed(1)}-${maxHeight.toStringAsFixed(1)})',
          ),
          const SizedBox(height: 8),
          Text(
            milestone,
            maxLines: widget.expanded ? null : 4,
            overflow: widget.expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => widget.onExpandedChanged(!widget.expanded),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(widget.expanded ? 'See less' : 'See more'),
            ),
          ),
          Text(
            'Expected WHO progress for this month (${profile.gender.label})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  IconData _iconForMonth(int month) {
    if (month == 0) return Icons.child_friendly;
    if (month <= 2) return Icons.baby_changing_station;
    if (month <= 4) return Icons.smart_toy;
    if (month <= 6) return Icons.airline_seat_recline_normal;
    if (month <= 8) return Icons.emoji_emotions;
    if (month <= 10) return Icons.toys;
    return Icons.accessibility_new;
  }

  String _milestoneForMonth(int month) {
    const milestones = <int, String>{
      0:
          'A quick note: baby development is not a strict schedule. Milestones happen within a normal range, and some skills show up gradually over several weeks, not all at once on a birthday. The guide below is based mainly on the CDC milestone checklists, the American Academy of Pediatrics’ \n\n'
          'During the newborn stage, babies mostly feed, sleep, cry, and react through built-in reflexes. Common early reflexes include rooting, sucking, grasping, stepping, and the Moro or startle reflex. Neck control is still very limited, so the head needs full support. Vision is best at close range, around 8 to 12 inches, which is just right for looking at a parent’s face during feeding. Newborns usually prefer faces and high-contrast patterns, can hear voices well, recognize some familiar sounds, and may recognize the smell of their mother’s breastmilk. It is also normal for a newborn to lose about 10% to 12% of birth weight at first, then begin gaining again by about 2 weeks.',
      1:
          'By the end of the first month, babies are usually more alert and responsive than they were right after birth. Movements are still jerky, but they start bringing their hands closer to their eyes and mouth, may move their head side to side while lying on the stomach, and still often keep their hands in tight fists. They usually focus best on things close to their face, may turn toward familiar voices, and continue to prefer faces and strong visual contrast. You may also notice that they listen when you talk and begin to move in response to your voice or touch.',
      2:
          'Around 2 months, babies usually become much more social. Many calm down when spoken to or picked up, look at faces, seem happy when a familiar person comes near, and smile when someone smiles or talks to them. They often make sounds other than crying, react to loud sounds, watch people move, and look at toys for a few seconds. Physically, they can usually hold the head up a bit during tummy time, move both arms and legs, open their hands briefly, and start bringing their hands toward the mouth more often.',
      3:
          'At 3 months, babies usually look much more active and intentional. Many can raise the head and chest when lying on the stomach, support the upper body with the arms, kick strongly, open and close the hands, bring a hand to the mouth, swipe at dangling objects, and grasp or shake a toy placed in the hand. They often watch faces closely, follow moving objects, recognize familiar people or objects at a distance, smile socially, enjoy play, babble, imitate some sounds, and turn toward sound. A lot of the newborn reflex-driven movement begins fading as more voluntary control appears.',
      4:
          'By 4 months, babies often smile on purpose to get attention and may chuckle when someone plays with them. They usually coo, make sounds back and forth with caregivers, and turn toward the sound of a familiar voice. Many are also more aware of feeding cues, such as opening the mouth when seeing the breast or bottle, and they often study their hands with real interest. Motor control improves too: head control becomes steadier, they may hold a toy when it is placed in the hand, swing at toys, bring hands to the mouth, and push up on the forearms during tummy time. At this age, babies also begin learning simple cause and effect, like noticing that kicking, shaking, or waving can make something happen.',
      5:
          'At about 5 months, many babies are in the middle of a big movement and learning jump. They are often pushing up higher on the arms, arching the back to lift the chest, rocking on the stomach, kicking hard, and making “swimming” motions with the arms and legs that help prepare them for rolling and crawling. Hand control gets better, so they bring objects to the mouth more easily and keep experimenting with how things feel, sound, and move. Socially, many become more expressive, more eager to reach and touch things, and more likely to laugh, babble, and demand help when they want something.',
      6:
          'By 6 months, many babies know familiar people, enjoy looking at themselves in a mirror, and laugh openly. They often take turns making sounds with a caregiver, blow raspberries, and make squeals. Exploration becomes more active: they put objects in the mouth, reach for wanted toys, and may close the lips to show they do not want more food. Physically, many roll from tummy to back, push up with straight arms during tummy time, and lean on their hands for support while sitting.',
      7:
          'At 7 months, many babies roll both ways, sit with less help and sometimes without hand support for short periods, bear weight through the legs when supported, reach with one hand, transfer objects from one hand to the other, and use a raking grasp instead of a true pincer grasp. Vision also sharpens, including better tracking of moving objects and fuller color vision. Language and social skills usually move forward too: many respond to their name, begin to react to “no,” babble strings of consonants, enjoy social play, look at mirror images with interest, and start searching for partly hidden objects.',
      8:
          'Around 8 months, babies often become much more mobile and curious. Many can sit without support, flip over quickly, and begin crawling, scooting, slithering, or rocking on hands and knees. Some never crawl in the usual way, and that can still be normal if both sides of the body are used well. Cognitively, this is a busy age: many babies love dropping, throwing, rolling, and waving objects to see what happens, and they begin understanding that objects still exist when hidden. For example, they may lift a scarf to look for a toy underneath. Communication also grows: many use pointing, reaching, crawling, or gestures to show what they want, while babble begins sounding more like real syllables such as “ba,” “da,” and “ma.” Socially, stranger anxiety and separation anxiety often begin to show up around this time.',
      9:
          'By 9 months, babies often show clearer emotions and stronger attachment. Many are shy, clingy, or fearful with strangers, react when a caregiver leaves, look when their name is called, and smile or laugh during peek-a-boo. They often make repeated sounds like “mamamama” or “bababababa” and lift their arms to be picked up. Problem-solving and hand use improve too: they may look for objects that fall out of sight, bang two objects together, move into a sitting position by themselves, sit without support, transfer items between hands, and rake food toward themselves with the fingers.',
      10:
          'At 10 months, many babies are more persistent and purposeful. Object permanence is usually much stronger by now, so they may keep searching for a hidden toy even after it has been moved. Many have already learned to crawl sometime between 7 and 10 months, while others may still scoot or slither. Their babbling often becomes more patterned, and they may use familiar sound combinations more often while understanding more of what adults say. Separation anxiety can also feel stronger at this stage, and the American Academy of Pediatrics notes that it commonly peaks sometime between 10 and 18 months.',
      11:
          'As babies near their first birthday, many are practicing late first-year skills even if they have not fully mastered them yet. Common things you may see include pulling up, moving along furniture, picking up tiny bits of food more neatly with the thumb and finger, understanding simple words better, and using gestures like pointing or waving. Some may say sounds like “mama” more intentionally, while others are still mostly communicating through gestures, babble, and facial expression. Movement is usually constant at this age, and many babies are eager to explore while repeatedly checking back with a parent for security. This month is best understood as a “working toward 1-year milestones” stage rather than a clean cutoff.',
      12:
          'By 12 months, many babies play simple games like pat-a-cake, wave bye-bye, call a parent “mama” or “dada” or another special name, and understand “no.” Many can put an object into a container, look for hidden items, pull to stand, cruise while holding furniture, drink from a cup when helped, and pick up tiny objects with a thumb-and-finger pincer grasp. MedlinePlus also notes that a typical 12-month-old may stand without holding on, walk alone or while holding one hand, sit down without help, bang two blocks together, turn thick pages in a book, point with the index finger, begin pretend play, follow simple commands, and say one or two additional words. Growth-wise, many 12-month-olds are about triple their birth weight.',
    };
    return milestones[month] ?? 'Can keep developing movement, language, and social interaction skills.';
  }
}

class TrendCharts extends StatelessWidget {
  const TrendCharts({super.key, required this.profile, required this.onDataChanged});

  final GrowthProfile profile;
  final Future<void> Function() onDataChanged;

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
        if (weightPoints.length >= 2) ...[
          _WeightChartCard(profile: profile, entries: weightPoints),
          const SizedBox(height: 12),
        ],
        if (weightPoints.isNotEmpty) ...[
          _WeightEntriesTableCard(
            profile: profile,
            entries: weightPoints,
            onDataChanged: onDataChanged,
          ),
          const SizedBox(height: 12),
        ],
        if (heightPoints.length >= 2) ...[
          _HeightChartCard(profile: profile, entries: heightPoints),
          const SizedBox(height: 12),
        ],
        if (heightPoints.isNotEmpty)
          _HeightEntriesTableCard(
            profile: profile,
            entries: heightPoints,
            onDataChanged: onDataChanged,
          ),
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
    final isBabyProfile = profile.ageInYears < 2;
    final ageMonths = [
      for (final entry in entries) AgeDisplayFormatter.monthsBetween(profile.birthDate, entry.date).toDouble(),
    ];
    final values = entries.map((e) => UnitConverter.toDisplayWeight(e.weightKg!, profile.weightUnit)).toList();
    final guidanceTarget = _referenceLine(ageMonths, profile, GrowthBand.median);
    final guidanceLow = _referenceLine(ageMonths, profile, GrowthBand.lowerBound);
    final allChartValues = [
      ...values,
      if (isBabyProfile) ...guidanceTarget.map((spot) => spot.y),
      if (isBabyProfile) ...guidanceLow.map((spot) => spot.y),
    ];
    final minValue = allChartValues.reduce(min);
    final maxValue = allChartValues.reduce(max);
    final hasRange = (maxValue - minValue).abs() > 0.001;
    final chartMinY = hasRange ? minValue : minValue - 0.5;
    final chartMaxY = hasRange ? maxValue : maxValue + 0.5;
    final chartWidth = max(680.0, entries.length * 90.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weight Trend (${profile.weightUnit.label})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SizedBox(
                  width: chartWidth,
                  height: 260,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 320,
                      child: LineChart(
                        LineChartData(
                      minX: -0.2,
                      maxX: entries.length - 0.8,
                      minY: chartMinY,
                      maxY: chartMaxY,
                      clipData: const FlClipData(top: false, bottom: false, left: false, right: false),
                      gridData: const FlGridData(show: true),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            reservedSize: 34,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if ((value - index).abs() > 0.001) return const SizedBox.shrink();
                              if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                              return SideTitleWidget(
                                meta: meta,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: index == 0 ? 12 : 0,
                                    right: index == entries.length - 1 ? 12 : 0,
                                  ),
                                  child: Text(_shortDateFormatter.format(entries[index].date)),
                                ),
                              );
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
                ),
              ),
            ),
            if (isBabyProfile)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Green = WHO median weight-for-age reference; Red = WHO lower-bound reference (about 3rd percentile).',
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _referenceLine(List<double> ageMonths, GrowthProfile profile, GrowthBand band) {
    return [
      for (var i = 0; i < ageMonths.length; i++)
        FlSpot(
          i.toDouble(),
          UnitConverter.toDisplayWeight(
            BabyGrowthReference.referenceWeightKgForAge(
              ageMonths[i],
              band: band,
              gender: profile.gender,
            ),
            profile.weightUnit,
          ),
        ),
    ];
  }

}

class _HeightChartCard extends StatelessWidget {
  const _HeightChartCard({required this.profile, required this.entries});

  final GrowthProfile profile;
  final List<MetricEntry> entries;

  @override
  Widget build(BuildContext context) {
    final isBabyProfile = profile.ageInYears < 2;
    final ageMonths = [
      for (final entry in entries) AgeDisplayFormatter.monthsBetween(profile.birthDate, entry.date).toDouble(),
    ];
    final values = entries.map((e) => UnitConverter.toDisplayHeight(e.heightCm!, profile.heightUnit)).toList();
    final guidanceTarget = _referenceLine(ageMonths, profile, GrowthBand.median);
    final guidanceLow = _referenceLine(ageMonths, profile, GrowthBand.lowerBound);
    final allChartValues = [
      ...values,
      if (isBabyProfile) ...guidanceTarget.map((spot) => spot.y),
      if (isBabyProfile) ...guidanceLow.map((spot) => spot.y),
    ];
    final minValue = allChartValues.reduce(min);
    final maxValue = allChartValues.reduce(max);
    final hasRange = (maxValue - minValue).abs() > 0.001;
    final chartMinY = hasRange ? minValue : minValue - 0.5;
    final chartMaxY = hasRange ? maxValue : maxValue + 0.5;
    final chartWidth = max(680.0, entries.length * 90.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Height Trend (${profile.heightUnit.label})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SizedBox(
                  width: chartWidth,
                  height: 260,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 320,
                      child: LineChart(
                        LineChartData(
                      minX: -0.2,
                      maxX: entries.length - 0.8,
                      minY: chartMinY,
                      maxY: chartMaxY,
                      clipData: const FlClipData(top: false, bottom: false, left: false, right: false),
                      gridData: const FlGridData(show: true),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            reservedSize: 34,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if ((value - index).abs() > 0.001) return const SizedBox.shrink();
                              if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                              return SideTitleWidget(
                                meta: meta,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: index == 0 ? 12 : 0,
                                    right: index == entries.length - 1 ? 12 : 0,
                                  ),
                                  child: Text(_shortDateFormatter.format(entries[index].date)),
                                ),
                              );
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
                ),
              ),
            ),
            if (isBabyProfile)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Green = WHO median length-for-age reference; Red = WHO lower-bound reference (about 3rd percentile).',
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _referenceLine(List<double> ageMonths, GrowthProfile profile, GrowthBand band) {
    return [
      for (var i = 0; i < ageMonths.length; i++)
        FlSpot(
          i.toDouble(),
          UnitConverter.toDisplayHeight(
            BabyGrowthReference.referenceHeightCmForAge(
              ageMonths[i],
              band: band,
              gender: profile.gender,
            ),
            profile.heightUnit,
          ),
        ),
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

class _WeightEntriesTableCard extends StatelessWidget {
  const _WeightEntriesTableCard({
    required this.profile,
    required this.entries,
    required this.onDataChanged,
  });

  final GrowthProfile profile;
  final List<MetricEntry> entries;
  final Future<void> Function() onDataChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]..sort((a, b) => b.date.compareTo(a.date));
    final showPercentile = profile.ageInYears < 18;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Date')),
              DataColumn(label: Text('Weight (${profile.weightUnit.label})')),
              if (showPercentile) const DataColumn(label: Text('Weight %ile')),
              const DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final entry in sorted)
                DataRow.byIndex(
                  index: entry.id,
                  color: MaterialStatePropertyAll(
                    BabyGrowthReference.weightColorForEntry(profile, entry).withOpacity(0.14),
                  ),
                  cells: [
                    DataCell(
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: BabyGrowthReference.weightColorForEntry(profile, entry),
                          ),
                          const SizedBox(width: 6),
                          Text(_shortDateFormatter.format(entry.date)),
                        ],
                      ),
                      onTap: () => _showWeightExplanation(context, entry),
                    ),
                    DataCell(
                      Text(
                        entry.weightKg == null
                            ? '-'
                            : UnitConverter.toDisplayWeight(entry.weightKg!, profile.weightUnit).toStringAsFixed(1),
                      ),
                      onTap: () => _showWeightExplanation(context, entry),
                    ),
                    if (showPercentile)
                      DataCell(
                        Text(BabyGrowthReference.weightPercentileLabel(profile, entry)),
                        onTap: () => _showWeightExplanation(context, entry),
                      ),
                    DataCell(
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Edit entry',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _showEditEntrySheet(context, entry, MeasurementType.weight),
                          ),
                          IconButton(
                            tooltip: 'Delete entry',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDeleteEntry(context, entry),
                          ),
                        ],
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

  Future<void> _confirmDeleteEntry(BuildContext context, MetricEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('Delete measurement from ${_shortDateFormatter.format(entry.date)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ProfileRepository.instance.deleteEntry(entry.id);
    await onDataChanged();
  }

  Future<void> _showEditEntrySheet(
    BuildContext context,
    MetricEntry entry,
    MeasurementType measurementType,
  ) async {
    final result = await showModalBottomSheet<AddEntryInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddEntrySheet(
        profile: profile,
        initialEntry: entry,
        editMeasurementType: measurementType,
      ),
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

  void _showWeightExplanation(BuildContext context, MetricEntry entry) {
    if (BabyGrowthReference._snapshotForDate(profile, entry.date) == null) {
      return;
    }

    final explanation = BabyGrowthReference.explainWeightEntry(profile, entry);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Weight explanation'),
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

class _HeightEntriesTableCard extends StatelessWidget {
  const _HeightEntriesTableCard({
    required this.profile,
    required this.entries,
    required this.onDataChanged,
  });

  final GrowthProfile profile;
  final List<MetricEntry> entries;
  final Future<void> Function() onDataChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]..sort((a, b) => b.date.compareTo(a.date));
    final showPercentile = profile.ageInYears < 18;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Date')),
              DataColumn(label: Text('Height (${profile.heightUnit.label})')),
              if (showPercentile) const DataColumn(label: Text('Height %ile')),
              const DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final entry in sorted)
                DataRow.byIndex(
                  index: entry.id,
                  color: MaterialStatePropertyAll(
                    BabyGrowthReference.heightColorForEntry(profile, entry).withOpacity(0.14),
                  ),
                  cells: [
                    DataCell(
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: BabyGrowthReference.heightColorForEntry(profile, entry),
                          ),
                          const SizedBox(width: 6),
                          Text(_shortDateFormatter.format(entry.date)),
                        ],
                      ),
                      onTap: () => _showHeightExplanation(context, entry),
                    ),
                    DataCell(
                      Text(
                        entry.heightCm == null
                            ? '-'
                            : UnitConverter.toDisplayHeight(entry.heightCm!, profile.heightUnit).toStringAsFixed(1),
                      ),
                      onTap: () => _showHeightExplanation(context, entry),
                    ),
                    if (showPercentile)
                      DataCell(
                        Text(BabyGrowthReference.heightPercentileLabel(profile, entry)),
                        onTap: () => _showHeightExplanation(context, entry),
                      ),
                    DataCell(
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Edit entry',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _showEditEntrySheet(context, entry, MeasurementType.height),
                          ),
                          IconButton(
                            tooltip: 'Delete entry',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDeleteEntry(context, entry),
                          ),
                        ],
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

  Future<void> _confirmDeleteEntry(BuildContext context, MetricEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('Delete measurement from ${_shortDateFormatter.format(entry.date)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ProfileRepository.instance.deleteEntry(entry.id);
    await onDataChanged();
  }

  Future<void> _showEditEntrySheet(
    BuildContext context,
    MetricEntry entry,
    MeasurementType measurementType,
  ) async {
    final result = await showModalBottomSheet<AddEntryInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddEntrySheet(
        profile: profile,
        initialEntry: entry,
        editMeasurementType: measurementType,
      ),
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

  void _showHeightExplanation(BuildContext context, MetricEntry entry) {
    if (BabyGrowthReference._snapshotForDate(profile, entry.date) == null) {
      return;
    }
    final explanation = BabyGrowthReference.explainHeightEntry(profile, entry);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Height explanation'),
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

enum MeasurementType { weight, height }

class AddEntryInput {
  const AddEntryInput({required this.date, this.weight, this.height});

  final DateTime date;
  final double? weight;
  final double? height;
}

class AddEntrySheet extends StatefulWidget {
  const AddEntrySheet({
    super.key,
    required this.profile,
    this.initialEntry,
    this.editMeasurementType,
  });

  final GrowthProfile profile;
  final MetricEntry? initialEntry;
  final MeasurementType? editMeasurementType;

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
            if (widget.editMeasurementType != MeasurementType.height) ...[
              TextFormField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Weight (${widget.profile.weightUnit.label}) • optional'),
                validator: _optionalPositive,
              ),
              const SizedBox(height: 8),
            ],
            if (widget.editMeasurementType != MeasurementType.weight)
              TextFormField(
                controller: _heightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Height (${widget.profile.heightUnit.label}) • optional'),
                validator: _optionalPositive,
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Measurement date'),
              subtitle: Text(_shortDateFormatter.format(_selectedDate)),
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
                final weight = widget.editMeasurementType == MeasurementType.height
                    ? null
                    : _parseOptional(_weightController.text);
                final height = widget.editMeasurementType == MeasurementType.weight
                    ? null
                    : _parseOptional(_heightController.text);
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
  late ProfileGender _gender;
  late DateTime _birthDate;
  late WeightUnit _weightUnit;
  late HeightUnit _heightUnit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _purpose = widget.profile.purpose;
    _gender = widget.profile.gender;
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
            const SizedBox(height: 8),
            DropdownButtonFormField<ProfileGender>(
              value: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: ProfileGender.values
                  .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _gender = value);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Birth date'),
              subtitle: Text(_birthDateFormatter.format(_birthDate)),
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
                          gender: _gender,
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

enum GrowthBand { lowerBound, median, upperBound }

class BabyGrowthReference {
  static const _snapshots = <ProfileGender, Map<int, BabyGrowthSnapshot>>{
    ProfileGender.male: {
      0: BabyGrowthSnapshot(
        minWeightKg: 2.6,
        avgWeightKg: 3.4,
        maxWeightKg: 4.5,
        minHeightCm: 46.5,
        avgHeightCm: 50.5,
        maxHeightCm: 54.5,
        ageLabel: 'newborn',
      ),
      3: BabyGrowthSnapshot(
        minWeightKg: 5.0,
        avgWeightKg: 6.4,
        maxWeightKg: 7.9,
        minHeightCm: 58.0,
        avgHeightCm: 62.0,
        maxHeightCm: 66.0,
        ageLabel: '3 months',
      ),
      6: BabyGrowthSnapshot(
        minWeightKg: 6.7,
        avgWeightKg: 8.1,
        maxWeightKg: 9.9,
        minHeightCm: 64.0,
        avgHeightCm: 68.0,
        maxHeightCm: 72.0,
        ageLabel: '6 months',
      ),
      9: BabyGrowthSnapshot(
        minWeightKg: 7.5,
        avgWeightKg: 9.1,
        maxWeightKg: 11.2,
        minHeightCm: 68.0,
        avgHeightCm: 73.0,
        maxHeightCm: 77.0,
        ageLabel: '9 months',
      ),
      12: BabyGrowthSnapshot(
        minWeightKg: 8.1,
        avgWeightKg: 9.9,
        maxWeightKg: 12.2,
        minHeightCm: 72.0,
        avgHeightCm: 77.0,
        maxHeightCm: 82.0,
        ageLabel: '12 months',
      ),
      18: BabyGrowthSnapshot(
        minWeightKg: 9.2,
        avgWeightKg: 11.4,
        maxWeightKg: 14.1,
        minHeightCm: 77.0,
        avgHeightCm: 83.0,
        maxHeightCm: 89.0,
        ageLabel: '18 months',
      ),
      24: BabyGrowthSnapshot(
        minWeightKg: 10.1,
        avgWeightKg: 12.7,
        maxWeightKg: 15.9,
        minHeightCm: 82.0,
        avgHeightCm: 88.0,
        maxHeightCm: 94.0,
        ageLabel: '24 months',
      ),
    },
    ProfileGender.female: {
      0: BabyGrowthSnapshot(
        minWeightKg: 2.4,
        avgWeightKg: 3.2,
        maxWeightKg: 4.2,
        minHeightCm: 45.8,
        avgHeightCm: 49.5,
        maxHeightCm: 53.5,
        ageLabel: 'newborn',
      ),
      3: BabyGrowthSnapshot(
        minWeightKg: 4.6,
        avgWeightKg: 5.8,
        maxWeightKg: 7.2,
        minHeightCm: 56.5,
        avgHeightCm: 60.0,
        maxHeightCm: 64.0,
        ageLabel: '3 months',
      ),
      6: BabyGrowthSnapshot(
        minWeightKg: 6.1,
        avgWeightKg: 7.4,
        maxWeightKg: 9.2,
        minHeightCm: 62.0,
        avgHeightCm: 65.7,
        maxHeightCm: 70.0,
        ageLabel: '6 months',
      ),
      9: BabyGrowthSnapshot(
        minWeightKg: 6.8,
        avgWeightKg: 8.3,
        maxWeightKg: 10.5,
        minHeightCm: 66.0,
        avgHeightCm: 70.5,
        maxHeightCm: 75.0,
        ageLabel: '9 months',
      ),
      12: BabyGrowthSnapshot(
        minWeightKg: 7.4,
        avgWeightKg: 9.0,
        maxWeightKg: 11.5,
        minHeightCm: 70.0,
        avgHeightCm: 74.5,
        maxHeightCm: 79.0,
        ageLabel: '12 months',
      ),
      18: BabyGrowthSnapshot(
        minWeightKg: 8.4,
        avgWeightKg: 10.3,
        maxWeightKg: 13.3,
        minHeightCm: 75.0,
        avgHeightCm: 80.5,
        maxHeightCm: 86.5,
        ageLabel: '18 months',
      ),
      24: BabyGrowthSnapshot(
        minWeightKg: 9.3,
        avgWeightKg: 11.7,
        maxWeightKg: 15.0,
        minHeightCm: 80.0,
        avgHeightCm: 86.0,
        maxHeightCm: 92.0,
        ageLabel: '24 months',
      ),
    },
  };

  static BabyGrowthSnapshot? summaryFor(GrowthProfile profile) {
    if (profile.ageInMonths > 24) return null;
    final snapshots = _snapshots[profile.gender]!;
    final nearestMonth = snapshots.keys.reduce(
      (a, b) => (profile.ageInMonths - a).abs() <= (profile.ageInMonths - b).abs() ? a : b,
    );
    return snapshots[nearestMonth];
  }

  static double referenceHeightCmForAge(
    double ageInMonths, {
    required GrowthBand band,
    required ProfileGender gender,
  }) {
    final snapshots = _snapshots[gender]!;
    if (snapshots.isEmpty) return 0;
    final keys = snapshots.keys.toList()..sort();
    final clampedMonth = ageInMonths.clamp(keys.first.toDouble(), keys.last.toDouble());
    var lowerMonth = keys.first;
    var upperMonth = keys.last;
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      if (key <= clampedMonth) lowerMonth = key;
      if (key >= clampedMonth) {
        upperMonth = key;
        break;
      }
    }

    double valueFor(BabyGrowthSnapshot snapshot) {
      switch (band) {
        case GrowthBand.lowerBound:
          return snapshot.minHeightCm;
        case GrowthBand.median:
          return snapshot.avgHeightCm;
        case GrowthBand.upperBound:
          return snapshot.maxHeightCm;
      }
    }

    final lowerSnapshot = snapshots[lowerMonth]!;
    final upperSnapshot = snapshots[upperMonth]!;
    if (lowerMonth == upperMonth) return valueFor(lowerSnapshot);
    final t = (clampedMonth - lowerMonth) / (upperMonth - lowerMonth);
    final lowerValue = valueFor(lowerSnapshot);
    final upperValue = valueFor(upperSnapshot);
    return lowerValue + (upperValue - lowerValue) * t;
  }

  static double referenceWeightKgForAge(
    double ageInMonths, {
    required GrowthBand band,
    required ProfileGender gender,
  }) {
    final snapshots = _snapshots[gender]!;
    if (snapshots.isEmpty) return 0;
    final keys = snapshots.keys.toList()..sort();
    final clampedMonth = ageInMonths.clamp(keys.first.toDouble(), keys.last.toDouble());
    var lowerMonth = keys.first;
    var upperMonth = keys.last;
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      if (key <= clampedMonth) lowerMonth = key;
      if (key >= clampedMonth) {
        upperMonth = key;
        break;
      }
    }

    double valueFor(BabyGrowthSnapshot snapshot) {
      switch (band) {
        case GrowthBand.lowerBound:
          return snapshot.minWeightKg;
        case GrowthBand.median:
          return snapshot.avgWeightKg;
        case GrowthBand.upperBound:
          return snapshot.maxWeightKg;
      }
    }

    final lowerSnapshot = snapshots[lowerMonth]!;
    final upperSnapshot = snapshots[upperMonth]!;
    if (lowerMonth == upperMonth) return valueFor(lowerSnapshot);
    final t = (clampedMonth - lowerMonth) / (upperMonth - lowerMonth);
    final lowerValue = valueFor(lowerSnapshot);
    final upperValue = valueFor(upperSnapshot);
    return lowerValue + (upperValue - lowerValue) * t;
  }

  static BabyGrowthSnapshot? _snapshotForDate(GrowthProfile profile, DateTime measuredDate) {
    final snapshots = _snapshots[profile.gender]!;
    final ageInMonths = AgeDisplayFormatter.monthsBetween(profile.birthDate, measuredDate);
    if (ageInMonths > 24) return null;
    final nearestMonth = snapshots.keys.reduce(
      (a, b) => (ageInMonths - a).abs() <= (ageInMonths - b).abs() ? a : b,
    );
    return snapshots[nearestMonth];
  }

  static String weightPercentileLabel(GrowthProfile profile, MetricEntry entry) {
    final percentile = _percentileForEntry(profile, entry, isWeight: true);
    if (percentile == null) return '-';
    return '${percentile.round()}th';
  }

  static String heightPercentileLabel(GrowthProfile profile, MetricEntry entry) {
    final percentile = _percentileForEntry(profile, entry, isWeight: false);
    if (percentile == null) return '-';
    return '${percentile.round()}th';
  }

  static double? _percentileForEntry(GrowthProfile profile, MetricEntry entry, {required bool isWeight}) {
    final ageInMonths = AgeDisplayFormatter.monthsBetween(profile.birthDate, entry.date).toDouble();
    final measured = isWeight ? entry.weightKg : entry.heightCm;
    if (measured == null) return null;

    final p3 = isWeight
        ? referenceWeightKgForAge(ageInMonths, band: GrowthBand.lowerBound, gender: profile.gender)
        : referenceHeightCmForAge(ageInMonths, band: GrowthBand.lowerBound, gender: profile.gender);
    final p50 = isWeight
        ? referenceWeightKgForAge(ageInMonths, band: GrowthBand.median, gender: profile.gender)
        : referenceHeightCmForAge(ageInMonths, band: GrowthBand.median, gender: profile.gender);
    final p97 = isWeight
        ? referenceWeightKgForAge(ageInMonths, band: GrowthBand.upperBound, gender: profile.gender)
        : referenceHeightCmForAge(ageInMonths, band: GrowthBand.upperBound, gender: profile.gender);

    if (measured <= p3) return 3;
    if (measured >= p97) return 97;
    if (measured <= p50) {
      return 3 + ((measured - p3) / max(0.0001, (p50 - p3))) * 47;
    }
    return 50 + ((measured - p50) / max(0.0001, (p97 - p50))) * 47;
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

  static Color weightColorForEntry(GrowthProfile profile, MetricEntry entry) {
    final snapshot = _snapshotForDate(profile, entry.date);
    if (snapshot == null || entry.weightKg == null) return Colors.blueGrey;
    final weight = entry.weightKg!;
    return (weight < snapshot.minWeightKg || weight > snapshot.maxWeightKg) ? Colors.red : Colors.green;
  }

  static Color heightColorForEntry(GrowthProfile profile, MetricEntry entry) {
    final snapshot = _snapshotForDate(profile, entry.date);
    if (snapshot == null || entry.heightCm == null) return Colors.blueGrey;
    final height = entry.heightCm!;
    return (height < snapshot.minHeightCm || height > snapshot.maxHeightCm) ? Colors.red : Colors.green;
  }

  static String explainWeightEntry(GrowthProfile profile, MetricEntry entry) {
    final snapshot = _snapshotForDate(profile, entry.date);
    if (snapshot == null) {
      return 'Weight references are shown through 24 months of age, so no weight interpretation is available for this date.';
    }

    final weight = entry.weightKg;
    if (weight == null) {
      return 'No weight was recorded in this entry.';
    }
    final details =
        'Weight recorded: ${weight.toStringAsFixed(1)} kg. '
        'Typical range for this age band: ${snapshot.minWeightKg.toStringAsFixed(1)}-${snapshot.maxWeightKg.toStringAsFixed(1)} kg '
        '(approx percentile: ${weightPercentileLabel(profile, entry)}).';

    final color = weightColorForEntry(profile, entry);
    final reason = color == Colors.red
        ? 'Clinical note: the weight is outside the expected reference range for age, so this row is highlighted in red.'
        : color == Colors.green
            ? 'Clinical note: the weight is within the expected reference range for age, so this row is highlighted in green.'
            : 'Clinical note: no interpretable weight was recorded in this entry.';
    final measuredAge = AgeDisplayFormatter.babyMonthsAndDays(
      profile.birthDate,
      asOf: entry.date,
    );
    return '$reason\n\n$details\n\nReference age band: ${snapshot.ageLabel} (measured at $measuredAge, ${profile.gender.label} reference).\n\nThese references are aligned to WHO Child Growth Standards for ages 0-24 months and are for guidance only. If you are concerned, consult your pediatrician.';
  }

  static String explainHeightEntry(GrowthProfile profile, MetricEntry entry) {
    final snapshot = _snapshotForDate(profile, entry.date);
    if (snapshot == null) {
      return 'Height references are shown through 24 months of age, so no height interpretation is available for this date.';
    }

    final height = entry.heightCm;
    if (height == null) {
      return 'No height was recorded in this entry.';
    }
    final details =
        'Length/height recorded: ${height.toStringAsFixed(1)} cm. '
        'Typical range for this age band: ${snapshot.minHeightCm.toStringAsFixed(1)}-${snapshot.maxHeightCm.toStringAsFixed(1)} cm '
        '(approx percentile: ${heightPercentileLabel(profile, entry)}).';

    final color = heightColorForEntry(profile, entry);
    final reason = color == Colors.red
        ? 'Clinical note: the height is outside the expected reference range for age, so this row is highlighted in red.'
        : color == Colors.green
            ? 'Clinical note: the height is within the expected reference range for age, so this row is highlighted in green.'
            : 'Clinical note: no interpretable height was recorded in this entry.';
    final measuredAge = AgeDisplayFormatter.babyMonthsAndDays(
      profile.birthDate,
      asOf: entry.date,
    );
    return '$reason\n\n$details\n\nReference age band: ${snapshot.ageLabel} (measured at $measuredAge, ${profile.gender.label} reference).\n\nThese references are aligned to WHO Child Growth Standards for ages 0-24 months and are for guidance only. If you are concerned, consult your pediatrician.';
  }
}
