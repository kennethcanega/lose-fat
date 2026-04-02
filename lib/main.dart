import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const HealthJourneyApp());
}

class HealthJourneyApp extends StatelessWidget {
  const HealthJourneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Growth Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const TrackerDashboard(),
    );
  }
}

class GrowthProfile {
  GrowthProfile({
    required this.id,
    required this.name,
    required this.purpose,
    required this.birthDate,
    required this.entries,
  });

  final String id;
  String name;
  String purpose;
  DateTime birthDate;
  final List<MetricEntry> entries;

  int get ageInMonths {
    final now = DateTime.now();
    return (now.year - birthDate.year) * 12 + now.month - birthDate.month;
  }

  int get ageInYears => ageInMonths ~/ 12;

  MetricEntry? get latest => entries.isEmpty ? null : entries.last;
}

class MetricEntry {
  const MetricEntry({
    required this.date,
    required this.weightKg,
    required this.heightCm,
  });

  final DateTime date;
  final double weightKg;
  final double heightCm;

  double get bmi {
    final heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }
}

class TrackerDashboard extends StatefulWidget {
  const TrackerDashboard({super.key});

  @override
  State<TrackerDashboard> createState() => _TrackerDashboardState();
}

class _TrackerDashboardState extends State<TrackerDashboard> {
  final List<GrowthProfile> _profiles = [
    GrowthProfile(
      id: 'baby_1',
      name: 'Profile 1 • Baby Emma',
      purpose: 'Baby development tracking',
      birthDate: DateTime.now().subtract(const Duration(days: 300)),
      entries: [
        MetricEntry(
          date: DateTime.now().subtract(const Duration(days: 180)),
          weightKg: 6.7,
          heightCm: 62,
        ),
        MetricEntry(
          date: DateTime.now().subtract(const Duration(days: 120)),
          weightKg: 7.9,
          heightCm: 67,
        ),
        MetricEntry(
          date: DateTime.now().subtract(const Duration(days: 60)),
          weightKg: 8.8,
          heightCm: 71,
        ),
      ],
    ),
    GrowthProfile(
      id: 'dad_1',
      name: 'Profile 2 • Father Alex',
      purpose: 'Weight loss journey',
      birthDate: DateTime(1989, 4, 5),
      entries: [
        MetricEntry(
          date: DateTime.now().subtract(const Duration(days: 90)),
          weightKg: 96,
          heightCm: 178,
        ),
        MetricEntry(
          date: DateTime.now().subtract(const Duration(days: 45)),
          weightKg: 91,
          heightCm: 178,
        ),
        MetricEntry(
          date: DateTime.now().subtract(const Duration(days: 7)),
          weightKg: 88.5,
          heightCm: 178,
        ),
      ],
    ),
  ];

  int _selectedIndex = 0;

  GrowthProfile get _selectedProfile => _profiles[_selectedIndex];

  @override
  Widget build(BuildContext context) {
    final profile = _selectedProfile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Growth & Weight Tracker'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final newEntry = await showModalBottomSheet<MetricEntry>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (context) => AddEntrySheet(profile: profile),
          );
          if (newEntry != null) {
            setState(() {
              profile.entries.add(newEntry);
              profile.entries.sort((a, b) => a.date.compareTo(b.date));
            });
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add measurement'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfilePicker(
            profiles: _profiles,
            selectedIndex: _selectedIndex,
            onProfileChanged: (index) => setState(() => _selectedIndex = index),
            onAddProfile: _addProfile,
          ),
          const SizedBox(height: 12),
          _ProfileOverviewCard(profile: profile),
          const SizedBox(height: 12),
          _AgeBasedInsightCard(profile: profile),
          const SizedBox(height: 16),
          _TrendCharts(profile: profile),
          const SizedBox(height: 16),
          _EntriesTable(profile: profile),
          const SizedBox(height: 64),
        ],
      ),
    );
  }

  Future<void> _addProfile() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final purposeController = TextEditingController();
    final ageController = TextEditingController();
    final weightController = TextEditingController();
    final heightController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create profile'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Profile name',
                    hintText: 'e.g., Baby Lucas',
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Name required'
                          : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: purposeController,
                  decoration: const InputDecoration(
                    labelText: 'Purpose',
                    hintText: 'e.g., Father weight loss journey',
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Purpose required'
                          : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Age (years)'),
                  validator: _requiredPositive,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: weightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Current weight (kg)'),
                  validator: _requiredPositive,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: heightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Current height (cm)'),
                  validator: _requiredPositive,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (created == true) {
      final age = int.parse(ageController.text.trim());
      final birthDate = DateTime(
        DateTime.now().year - age,
        DateTime.now().month,
        DateTime.now().day,
      );
      setState(() {
        _profiles.add(
          GrowthProfile(
            id: 'profile_${_profiles.length + 1}',
            name: nameController.text.trim(),
            purpose: purposeController.text.trim(),
            birthDate: birthDate,
            entries: [
              MetricEntry(
                date: DateTime.now(),
                weightKg: double.parse(weightController.text.trim()),
                heightCm: double.parse(heightController.text.trim()),
              ),
            ],
          ),
        );
        _selectedIndex = _profiles.length - 1;
      });
    }
  }

  String? _requiredPositive(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      return 'Enter a positive value';
    }
    return null;
  }
}

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({
    required this.profiles,
    required this.selectedIndex,
    required this.onProfileChanged,
    required this.onAddProfile,
  });

  final List<GrowthProfile> profiles;
  final int selectedIndex;
  final ValueChanged<int> onProfileChanged;
  final VoidCallback onAddProfile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Profiles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < profiles.length; i++)
                  ChoiceChip(
                    label: Text(profiles[i].name),
                    selected: i == selectedIndex,
                    onSelected: (_) => onProfileChanged(i),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.person_add),
                  label: const Text('New profile'),
                  onPressed: onAddProfile,
                ),
              ],
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
            Text(
              profile.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text('Age: ${profile.ageInYears}y ${profile.ageInMonths % 12}m'),
            Text('Purpose: ${profile.purpose}'),
            const SizedBox(height: 10),
            if (latest == null)
              const Text('No measurements yet. Add first entry to view trends.')
            else
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _KpiTile(label: 'Weight', value: '${latest.weightKg.toStringAsFixed(1)} kg'),
                  _KpiTile(label: 'Height', value: '${latest.heightCm.toStringAsFixed(1)} cm'),
                  _KpiTile(label: 'BMI', value: latest.bmi.toStringAsFixed(1)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value});

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
    final insight = _buildInsight(profile, latest);
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.auto_graph),
            const SizedBox(width: 12),
            Expanded(child: Text(insight)),
          ],
        ),
      ),
    );
  }

  String _buildInsight(GrowthProfile profile, MetricEntry? latest) {
    if (latest == null) {
      return 'Add measurements to generate age-based recommendations.';
    }
    if (profile.ageInYears < 2) {
      return 'Infant/toddler mode: prioritize steady growth curves in weight and height rather than BMI targets.';
    }
    final bmi = latest.bmi;
    final status = switch (bmi) {
      < 18.5 => 'under the adult healthy range',
      < 25 => 'in the adult healthy range',
      < 30 => 'in the overweight range',
      _ => 'in the obesity range',
    };
    return 'Adult mode: current BMI is ${bmi.toStringAsFixed(1)}, which is $status. Track gradual changes week-to-week.';
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
          child: Text('At least 2 entries are needed for charts.'),
        ),
      );
    }

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(height: 220, child: _WeightLineChart(profile: profile)),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(height: 220, child: _HeightBarChart(profile: profile)),
          ),
        ),
      ],
    );
  }
}

class _WeightLineChart extends StatelessWidget {
  const _WeightLineChart({required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final sorted = [...profile.entries]..sort((a, b) => a.date.compareTo(b.date));
    final minWeight = sorted.map((e) => e.weightKg).reduce(min) - 2;
    final maxWeight = sorted.map((e) => e.weightKg).reduce(max) + 2;

    return LineChart(
      LineChartData(
        minY: minWeight,
        maxY: maxWeight,
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= sorted.length) {
                  return const SizedBox.shrink();
                }
                return Text(DateFormat.Md().format(sorted[index].date));
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            spots: [
              for (var i = 0; i < sorted.length; i++)
                FlSpot(i.toDouble(), sorted[i].weightKg),
            ],
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}

class _HeightBarChart extends StatelessWidget {
  const _HeightBarChart({required this.profile});

  final GrowthProfile profile;

  @override
  Widget build(BuildContext context) {
    final sorted = [...profile.entries]..sort((a, b) => a.date.compareTo(b.date));

    return BarChart(
      BarChartData(
        barGroups: [
          for (var i = 0; i < sorted.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: sorted[i].heightCm,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= sorted.length) {
                  return const SizedBox.shrink();
                }
                return Text(DateFormat.Md().format(sorted[index].date));
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('History', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              const Text('No measurements yet.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Weight (kg)')),
                    DataColumn(label: Text('Height (cm)')),
                    DataColumn(label: Text('BMI')),
                  ],
                  rows: [
                    for (final entry in sorted)
                      DataRow(cells: [
                        DataCell(Text(DateFormat.yMMMd().format(entry.date))),
                        DataCell(Text(entry.weightKg.toStringAsFixed(1))),
                        DataCell(Text(entry.heightCm.toStringAsFixed(1))),
                        DataCell(Text(entry.bmi.toStringAsFixed(1))),
                      ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
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
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add measurement for ${widget.profile.name}'),
            const SizedBox(height: 12),
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
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Measurement date'),
              subtitle: Text(DateFormat.yMMMd().format(_selectedDate)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: widget.profile.birthDate,
                  lastDate: DateTime.now(),
                  initialDate: _selectedDate,
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                }
              },
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                if (!_formKey.currentState!.validate()) {
                  return;
                }
                Navigator.pop(
                  context,
                  MetricEntry(
                    date: _selectedDate,
                    weightKg: double.parse(_weightController.text),
                    heightCm: double.parse(_heightController.text),
                  ),
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

  String? _requiredPositive(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      return 'Enter a positive value';
    }
    return null;
  }
}
