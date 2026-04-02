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
    final savedId = await ProfileRepository.instance.getSelectedProfileId();

    setState(() {
      _profiles = profiles;
      _selectedProfileId = savedId;
      _loading = false;
    });
  }

  Future<void> _register(CreateProfileInput input) async {
    await ProfileRepository.instance.createProfile(input);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_profiles.isEmpty) {
      return RegistrationScreen(onCreateProfile: _register);
    }

    return TrackerDashboard(
      profiles: _profiles,
      selectedProfileId: _selectedProfileId,
      onDataChanged: _load,
      onSelectProfile: (id) async {
        await ProfileRepository.instance.setSelectedProfileId(id);
        setState(() => _selectedProfileId = id);
      },
    );
  }
}

class GrowthProfile {
  const GrowthProfile({
    required this.id,
    required this.name,
    required this.purpose,
    required this.age,
    required this.entries,
  });

  final int id;
  final String name;
  final String purpose;
  final int age;
  final List<MetricEntry> entries;

  MetricEntry? get latest => entries.isEmpty ? null : entries.last;
}

class MetricEntry {
  const MetricEntry({
    required this.id,
    required this.profileId,
    required this.date,
    required this.weightKg,
    required this.heightCm,
  });

  final int id;
  final int profileId;
  final DateTime date;
  final double weightKg;
  final double heightCm;

  double get bmi => weightKg / pow(heightCm / 100, 2);
}

class CreateProfileInput {
  const CreateProfileInput({
    required this.name,
    required this.purpose,
    required this.age,
    required this.weightKg,
    required this.heightCm,
  });

  final String name;
  final String purpose;
  final int age;
  final double weightKg;
  final double heightCm;
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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE profiles(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            purpose TEXT NOT NULL,
            age INTEGER NOT NULL,
            created_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE entries(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            weight_kg REAL NOT NULL,
            height_cm REAL NOT NULL,
            FOREIGN KEY(profile_id) REFERENCES profiles(id) ON DELETE CASCADE
          );
        ''');
      },
    );
  }

  Future<List<GrowthProfile>> fetchProfiles() async {
    final db = _db!;
    final profilesRaw = await db.query('profiles', orderBy: 'created_at ASC');
    final entriesRaw = await db.query('entries', orderBy: 'date ASC');

    final entriesByProfile = <int, List<MetricEntry>>{};
    for (final row in entriesRaw) {
      final entry = MetricEntry(
        id: row['id'] as int,
        profileId: row['profile_id'] as int,
        date: DateTime.parse(row['date'] as String),
        weightKg: (row['weight_kg'] as num).toDouble(),
        heightCm: (row['height_cm'] as num).toDouble(),
      );
      entriesByProfile.putIfAbsent(entry.profileId, () => []).add(entry);
    }

    return profilesRaw
        .map(
          (row) => GrowthProfile(
            id: row['id'] as int,
            name: row['name'] as String,
            purpose: row['purpose'] as String,
            age: row['age'] as int,
            entries: entriesByProfile[row['id'] as int] ?? [],
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
        'age': input.age,
        'created_at': DateTime.now().toIso8601String(),
      });

      await txn.insert('entries', {
        'profile_id': profileId,
        'date': DateTime.now().toIso8601String(),
        'weight_kg': input.weightKg,
        'height_cm': input.heightCm,
      });

      await setSelectedProfileId(profileId);
    });
  }

  Future<void> addEntry({
    required int profileId,
    required DateTime date,
    required double weightKg,
    required double heightCm,
  }) async {
    final db = _db!;
    await db.insert('entries', {
      'profile_id': profileId,
      'date': date.toIso8601String(),
      'weight_kg': weightKg,
      'height_cm': heightCm,
    });
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
      appBar: AppBar(title: const Text('Register first profile')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CreateProfileForm(onSubmit: onCreateProfile),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrackerDashboard extends StatefulWidget {
  const TrackerDashboard({
    super.key,
    required this.profiles,
    required this.selectedProfileId,
    required this.onSelectProfile,
    required this.onDataChanged,
  });

  final List<GrowthProfile> profiles;
  final int? selectedProfileId;
  final ValueChanged<int> onSelectProfile;
  final Future<void> Function() onDataChanged;

  @override
  State<TrackerDashboard> createState() => _TrackerDashboardState();
}

class _TrackerDashboardState extends State<TrackerDashboard> {
  GrowthProfile get _selectedProfile {
    if (widget.selectedProfileId == null) return widget.profiles.first;
    return widget.profiles.firstWhere(
      (p) => p.id == widget.selectedProfileId,
      orElse: () => widget.profiles.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _selectedProfile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Growth & Weight Tracker'),
        actions: [
          IconButton(
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Create profile'),
                  content: SizedBox(
                    width: 520,
                    child: CreateProfileForm(
                      onSubmit: (input) async {
                        await ProfileRepository.instance.createProfile(input);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              );
              await widget.onDataChanged();
            },
            icon: const Icon(Icons.person_add),
            tooltip: 'Add profile',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final entry = await showModalBottomSheet<_AddEntryResult>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => AddEntrySheet(profile: profile),
          );
          if (entry != null) {
            await ProfileRepository.instance.addEntry(
              profileId: profile.id,
              date: entry.date,
              weightKg: entry.weightKg,
              heightCm: entry.heightCm,
            );
            await widget.onDataChanged();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add measurement'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfilePicker(
            profiles: widget.profiles,
            selectedProfileId: profile.id,
            onProfileChanged: widget.onSelectProfile,
          ),
          const SizedBox(height: 12),
          _ProfileOverviewCard(profile: profile),
          const SizedBox(height: 12),
          _AgeBasedInsightCard(profile: profile),
          const SizedBox(height: 12),
          _TrendCharts(profile: profile),
          const SizedBox(height: 12),
          _EntriesTable(profile: profile),
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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _purposeController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: _requiredText,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _purposeController,
            decoration: const InputDecoration(labelText: 'Purpose for using app'),
            validator: _requiredText,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Age (years)'),
            validator: _requiredPositive,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Current weight (kg)'),
            validator: _requiredPositive,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _heightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Current height (cm)'),
            validator: _requiredPositive,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    if (!_formKey.currentState!.validate()) return;
                    setState(() => _saving = true);
                    await widget.onSubmit(
                      CreateProfileInput(
                        name: _nameController.text.trim(),
                        purpose: _purposeController.text.trim(),
                        age: int.parse(_ageController.text.trim()),
                        weightKg: double.parse(_weightController.text.trim()),
                        heightCm: double.parse(_heightController.text.trim()),
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
    );
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  String? _requiredPositive(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final number = double.tryParse(value);
    if (number == null || number <= 0) return 'Enter a positive value';
    return null;
  }
}

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({
    required this.profiles,
    required this.selectedProfileId,
    required this.onProfileChanged,
  });

  final List<GrowthProfile> profiles;
  final int selectedProfileId;
  final ValueChanged<int> onProfileChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final profile in profiles)
              ChoiceChip(
                label: Text(profile.name),
                selected: profile.id == selectedProfileId,
                onSelected: (_) => onProfileChanged(profile.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileOverviewCard extends StatelessWidget {
  const _ProfileOverviewCard({required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final latest = profile.latest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile.name, style: Theme.of(context).textTheme.titleLarge),
            Text('Purpose: ${profile.purpose}'),
            Text('Age: ${profile.age} years'),
            const SizedBox(height: 10),
            if (latest != null)
              Wrap(
                spacing: 16,
                children: [
                  _Kpi(label: 'Weight', value: '${latest.weightKg.toStringAsFixed(1)} kg'),
                  _Kpi(label: 'Height', value: '${latest.heightCm.toStringAsFixed(1)} cm'),
                  _Kpi(label: 'BMI', value: latest.bmi.toStringAsFixed(1)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});

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

class _AgeBasedInsightCard extends StatelessWidget {
  const _AgeBasedInsightCard({required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final latest = profile.latest;
    final text = latest == null
        ? 'Add measurements to generate insights.'
        : profile.age < 2
            ? 'Infant/toddler mode: focus on steady growth curves over strict BMI targets.'
            : 'Adult mode: BMI ${latest.bmi.toStringAsFixed(1)}. Focus on gradual, sustainable changes.';
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [const Icon(Icons.auto_graph), const SizedBox(width: 8), Expanded(child: Text(text))],
        ),
      ),
    );
  }
}

class _TrendCharts extends StatelessWidget {
  const _TrendCharts({required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    if (profile.entries.length < 2) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Add at least 2 measurements to view charts.'),
        ),
      );
    }

    final sorted = [...profile.entries]..sort((a, b) => a.date.compareTo(b.date));
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(height: 220, child: _WeightChart(entries: sorted)),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(height: 220, child: _HeightChart(entries: sorted)),
          ),
        ),
      ],
    );
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.entries});

  final List<MetricEntry> entries;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: entries.map((e) => e.weightKg).reduce(min) - 2,
        maxY: entries.map((e) => e.weightKg).reduce(max) + 2,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                return Text(DateFormat.Md().format(entries[i].date));
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            spots: [for (var i = 0; i < entries.length; i++) FlSpot(i.toDouble(), entries[i].weightKg)],
            dotData: const FlDotData(show: true),
            barWidth: 3,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _HeightChart extends StatelessWidget {
  const _HeightChart({required this.entries});

  final List<MetricEntry> entries;

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].heightCm,
                  width: 16,
                  color: Theme.of(context).colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                return Text(DateFormat.Md().format(entries[i].date));
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _EntriesTable extends StatelessWidget {
  const _EntriesTable({required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final sorted = [...profile.entries]..sort((a, b) => b.date.compareTo(a.date));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Weight (kg)')),
              DataColumn(label: Text('Height (cm)')),
              DataColumn(label: Text('BMI')),
            ],
            rows: [
              for (final e in sorted)
                DataRow(cells: [
                  DataCell(Text(DateFormat.yMMMd().format(e.date))),
                  DataCell(Text(e.weightKg.toStringAsFixed(1))),
                  DataCell(Text(e.heightCm.toStringAsFixed(1))),
                  DataCell(Text(e.bmi.toStringAsFixed(1))),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddEntryResult {
  const _AddEntryResult({
    required this.date,
    required this.weightKg,
    required this.heightCm,
  });

  final DateTime date;
  final double weightKg;
  final double heightCm;
}

class AddEntrySheet extends StatefulWidget {
  const AddEntrySheet({super.key, required this.profile});

  final GrowthProfile profile;

  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add measurement for ${widget.profile.name}'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (kg)'),
              validator: _requiredPositive,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Height (cm)'),
              validator: _requiredPositive,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Measurement date'),
              subtitle: Text(DateFormat.yMMMd().format(_date)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  initialDate: _date,
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            FilledButton(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(
                  context,
                  _AddEntryResult(
                    date: _date,
                    weightKg: double.parse(_weightController.text.trim()),
                    heightCm: double.parse(_heightController.text.trim()),
                  ),
                );
              },
              child: const Text('Save entry'),
            ),
          ],
        ),
      ),
    );
  }

  String? _requiredPositive(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final n = double.tryParse(value);
    if (n == null || n <= 0) return 'Enter a positive value';
    return null;
  }
}
