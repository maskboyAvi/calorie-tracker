import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../domain/models.dart';
import '../domain/nutrition_validation.dart';
import '../domain/recurrence.dart';
import '../domain/weekly_calories.dart';
import '../services/ai_assistant.dart';
import '../services/food_search.dart';
import '../state/tracker_controller.dart';

final class TrackerScope extends InheritedNotifier<TrackerController> {
  const TrackerScope({
    super.key,
    required TrackerController controller,
    required super.child,
  }) : super(notifier: controller);
  static TrackerController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TrackerScope>()!.notifier!;
}

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = TrackerScope.of(context);
    return PageFrame(
      title: 'Activity',
      subtitle: 'Your weekly plan',
      children: [
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _workoutDialog(context, c),
              icon: const Icon(Icons.add),
              label: const Text('Plan workout'),
            ),
            OutlinedButton.icon(
              onPressed: () => _quickActivityPlan(context, c, 'Run'),
              icon: const Icon(Icons.directions_run),
              label: const Text('Plan a run'),
            ),
            OutlinedButton.icon(
              onPressed: () => _quickActivityPlan(context, c, 'Rest'),
              icon: const Icon(Icons.self_improvement),
              label: const Text('Rest day'),
            ),
            OutlinedButton.icon(
              onPressed: () => _runLogDialog(context, c),
              icon: const Icon(Icons.directions_run),
              label: const Text('Log run'),
            ),
          ],
        ),
        if (c.workoutPlans.isEmpty)
          const _EmptyCard(
            icon: Icons.event_note,
            title: 'Plan your week',
            text: 'Schedule gym sessions, runs and rest days.',
          ),
        ...c.workoutPlans.map((p) {
          final data = jsonDecode(p['data'] as String) as Map<String, dynamic>;
          final exerciseList = data['exercises'] as List? ?? [];
          final goals = data['goals'] as Map? ?? {};
          final runGoals =
              goals['distance'] == null &&
                  goals['duration'] == null &&
                  goals['pace'] == null
              ? ''
              : ' · ${goals['distance'] == null ? '' : '${goals['distance']} km'}${goals['duration'] == null ? '' : ' · ${goals['duration']} min'}${goals['pace'] == null ? '' : ' · ${goals['pace']} min/km'}';
          return SurfaceCard(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    p['kind'] == 'Run'
                        ? Icons.directions_run
                        : p['kind'] == 'Rest'
                        ? Icons.self_improvement
                        : Icons.fitness_center,
                  ),
                  title: Text(p['name'] as String),
                  subtitle: Text(
                    '${p['date'] as String} · ${p['kind'] as String}${p['kind'] == 'Run' ? runGoals : ''}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'complete') await c.toggleWorkout(p);
                      if (action == 'edit' && p['kind'] == 'Gym') {
                        if (context.mounted) {
                          await _workoutDialog(context, c, existing: p);
                        }
                      }
                      if (action == 'edit' && p['kind'] != 'Gym') {
                        if (context.mounted) {
                          await _quickActivityPlan(
                            context,
                            c,
                            p['kind'] as String,
                            existing: p,
                          );
                        }
                      }
                      if (action == 'repeat') {
                        await c.planWorkout(
                          id: const Uuid().v4(),
                          date: dayKey(
                            DateTime.parse(p['date'] as String)
                                .add(const Duration(days: 7)),
                          ),
                          kind: p['kind'] as String,
                          name: p['name'] as String,
                          data: data,
                        );
                      }
                      if (action == 'delete') {
                        if (p['isOccurrence'] == true) {
                          if (!context.mounted) return;
                          final single = await _askSeriesScope(
                            context,
                            'Cancel',
                          );
                          if (single == true) {
                            await c.deleteWorkout(p['id'] as String);
                          } else if (single == false) {
                            await c.deleteWorkoutSeries(
                              p['seriesId'] as String,
                            );
                          }
                        } else {
                          await c.deleteWorkout(p['id'] as String);
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'complete',
                        child: Text(
                          (p['completed'] as num?) == 1
                              ? 'Mark incomplete'
                              : 'Mark complete',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(
                          p['isOccurrence'] == true
                              ? 'Edit occurrence / series'
                              : 'Edit',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'repeat',
                        child: Text('Repeat next week'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          p['isOccurrence'] == true
                              ? 'Cancel occurrence / series'
                              : 'Delete',
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < exerciseList.length; i++)
                  ..._exerciseSetRows(
                    context,
                    c,
                    p,
                    exerciseList[i] as Map<String, dynamic>,
                    i,
                  ),
              ],
            ),
          );
        }),
        const SectionTitle('Run history'),
        if (c.runLogs.isEmpty)
          const _EmptyCard(
            icon: Icons.directions_run,
            title: 'No runs logged yet',
            text: 'Add a run to track distance, time and average pace.',
          ),
        ...c.runLogs.map((r) {
          final km = (r['distance_km'] as num).toDouble(),
              min = (r['duration_min'] as num).toDouble();
          return SurfaceCard(
            child: ListTile(
              leading: const Icon(Icons.directions_run),
              title: Text('${fmt(km, digits: 2)} km · ${fmt(min)} min'),
              subtitle: Text(
                '${r['date'] as String} · ${fmt(min / km, digits: 1)} min/km',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') _runLogDialog(context, c, existing: r);
                  if (action == 'delete') c.deleteRun(r['id'] as String);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

List<Widget> _exerciseSetRows(
  BuildContext context,
  TrackerController c,
  Map<String, Object?> plan,
  Map<String, dynamic> exercise,
  int exerciseIndex,
) {
  final sets = exercise['sets'] as List? ?? [];
  return [
    Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '${exercise['name']} · ${exercise['muscle']}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    for (var i = 0; i < sets.length; i++)
      CheckboxListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 24, right: 12),
        title: Text('Set ${i + 1}'),
        subtitle: Text(
          '${sets[i]['targetReps']} reps · ${sets[i]['targetKg']} kg${exercise['notes'].toString().isEmpty ? '' : ' · ${exercise['notes']}'}',
        ),
        value: sets[i]['completed'] as bool? ?? false,
        onChanged: (_) => c.toggleWorkoutSet(plan, exerciseIndex, i),
      ),
  ];
}

Future<void> _quickActivityPlan(
  BuildContext context,
  TrackerController c,
  String kind, {
  Map<String, Object?>? existing,
}) async {
  final data = existing == null
      ? null
      : jsonDecode(existing['data'] as String) as Map<String, dynamic>;
  final seriesData = existing?['isOccurrence'] == true
      ? jsonDecode(existing!['seriesData'] as String) as Map<String, dynamic>
      : data;
  final goals = data?['goals'] as Map? ?? {};
  final initialRule = RepeatRule.fromMap(data?['recurrence'] as Map?);
  var repeatRule = initialRule;
  final name = TextEditingController(
        text:
            existing?['name'] as String? ?? (kind == 'Rest' ? 'Rest day' : ''),
      ),
      date = TextEditingController(
        text: existing?['date'] as String? ?? c.selectedDate,
      );
  final distance = TextEditingController(
        text: goals['distance']?.toString() ?? '',
      ),
      duration = TextEditingController(
        text: goals['duration']?.toString() ?? '',
      ),
      pace = TextEditingController(text: goals['pace']?.toString() ?? '');
  final result = await showDialog<List<String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Plan $kind' : 'Edit $kind plan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: kind == 'Run' ? 'Run name' : 'Rest day note',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: date,
              decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
            ),
            if (kind == 'Run') const SizedBox(height: 8),
            if (kind == 'Run')
              TextField(
                controller: distance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Distance goal (km)',
                ),
              ),
            const SizedBox(height: 12),
            _RepeatScheduleEditor(
              startDate: date.text,
              initial: initialRule,
              onChanged: (rule) => repeatRule = rule,
            ),
            if (kind == 'Run') const SizedBox(height: 8),
            if (kind == 'Run')
              TextField(
                controller: duration,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Duration goal (minutes)',
                ),
              ),
            if (kind == 'Run') const SizedBox(height: 8),
            if (kind == 'Run')
              TextField(
                controller: pace,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Pace goal (min/km)',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, [
            name.text,
            date.text,
            distance.text,
            duration.text,
            pace.text,
          ]),
          child: const Text('Save plan'),
        ),
      ],
    ),
  );
  if (result == null || result[0].trim().isEmpty) return;
  if (!context.mounted) return;
  final singleOccurrence = existing?['isOccurrence'] == true
      ? await _askSeriesScope(context, 'Edit')
      : false;
  if (singleOccurrence == null) return;
  final planData = <String, Object?>{
    'goals': {
      'distance': double.tryParse(result[2]),
      'duration': double.tryParse(result[3]),
      'pace': double.tryParse(result[4]),
    },
    'recurrence': repeatRule.toMap(),
    if (seriesData?['excludedDates'] != null)
      'excludedDates': seriesData!['excludedDates'],
    if (seriesData?['occurrenceData'] != null)
      'occurrenceData': seriesData!['occurrenceData'],
    if (seriesData?['occurrenceOverrides'] != null)
      'occurrenceOverrides': seriesData!['occurrenceOverrides'],
  };
  if (singleOccurrence) {
    await c.updateWorkoutOccurrence(
      occurrenceId: existing!['id'] as String,
      name: result[0],
      kind: kind,
      occurrenceData: planData,
    );
    return;
  }
  await c.planWorkout(
    id:
        existing?['seriesId'] as String? ??
        existing?['id'] as String? ??
        const Uuid().v4(),
    date: existing?['seriesStartDate'] as String? ?? result[1],
    kind: kind,
    name: result[0],
    data: planData,
    completed: existing?['isOccurrence'] == true
        ? false
        : existing?['completed'] == 1,
  );
}

Future<bool?> _askSeriesScope(BuildContext context, String action) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action recurring activity'),
        content: const Text('Apply this to one date or the entire series?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('This occurrence'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Entire series'),
          ),
        ],
      ),
    );

Future<void> _workoutDialog(
  BuildContext context,
  TrackerController c, {
  Map<String, Object?>? existing,
}) async {
  final result = await showDialog<_WorkoutPlanResult>(
    context: context,
    builder: (_) => _WorkoutPlanDialog(existing: existing),
  );
  if (result == null) return;
  if (!context.mounted) return;
  final singleOccurrence = existing?['isOccurrence'] == true
      ? await _askSeriesScope(context, 'Edit')
      : false;
  if (singleOccurrence == null) return;
  final originalData = existing == null
      ? <String, dynamic>{}
      : jsonDecode(
          existing['isOccurrence'] == true
              ? existing['seriesData'] as String
              : existing['data'] as String,
        ) as Map<String, dynamic>;
  final planData = <String, Object?>{
    'exercises': result.exercises,
    'recurrence': result.repeatRule.toMap(),
    if (originalData['excludedDates'] != null)
      'excludedDates': originalData['excludedDates'],
    if (originalData['occurrenceData'] != null)
      'occurrenceData': originalData['occurrenceData'],
    if (originalData['occurrenceOverrides'] != null)
      'occurrenceOverrides': originalData['occurrenceOverrides'],
  };
  if (singleOccurrence) {
    await c.updateWorkoutOccurrence(
      occurrenceId: existing!['id'] as String,
      name: result.name,
      kind: 'Gym',
      occurrenceData: planData,
    );
    return;
  }
  await c.planWorkout(
    id:
        existing?['seriesId'] as String? ??
        existing?['id'] as String? ??
        const Uuid().v4(),
    date: existing?['seriesStartDate'] as String? ?? result.date,
    kind: 'Gym',
    name: result.name,
    data: planData,
    completed: existing?['isOccurrence'] == true
        ? false
        : existing?['completed'] == 1,
  );
}

class _WorkoutPlanResult {
  const _WorkoutPlanResult(
    this.name,
    this.date,
    this.exercises,
    this.repeatRule,
  );
  final String name, date;
  final List<Map<String, Object?>> exercises;
  final RepeatRule repeatRule;
}

class _ExerciseDraft {
  _ExerciseDraft({
    String name = '',
    String muscle = '',
    String notes = '',
    String reps = '10',
    String weight = '',
    int setCount = 3,
  }) : name = TextEditingController(text: name),
       muscle = TextEditingController(text: muscle),
       notes = TextEditingController(text: notes),
       reps = TextEditingController(text: reps),
       weight = TextEditingController(text: weight),
       setCount = TextEditingController(text: setCount.toString());
  final TextEditingController name, muscle, notes, reps, weight, setCount;
  void dispose() {
    name.dispose();
    muscle.dispose();
    notes.dispose();
    reps.dispose();
    weight.dispose();
    setCount.dispose();
  }
}

class _WorkoutPlanDialog extends StatefulWidget {
  const _WorkoutPlanDialog({this.existing});
  final Map<String, Object?>? existing;
  @override
  State<_WorkoutPlanDialog> createState() => _WorkoutPlanDialogState();
}

class _WorkoutPlanDialogState extends State<_WorkoutPlanDialog> {
  late final TextEditingController name, date;
  late RepeatRule repeatRule;
  final exercises = <_ExerciseDraft>[];
  @override
  void initState() {
    super.initState();
    final data = widget.existing == null
        ? null
        : jsonDecode(widget.existing!['data'] as String)
              as Map<String, dynamic>;
    repeatRule = RepeatRule.fromMap(data?['recurrence'] as Map?);
    name = TextEditingController(
      text: widget.existing?['name'] as String? ?? '',
    );
    date = TextEditingController(
      text: widget.existing?['date'] as String? ?? dayKey(),
    );
    for (final item in (data?['exercises'] as List? ?? [])) {
      final e = item as Map;
      exercises.add(
        _ExerciseDraft(
          name: e['name']?.toString() ?? '',
          muscle: e['muscle']?.toString() ?? '',
          notes: e['notes']?.toString() ?? '',
          reps: e['reps']?.toString() ?? '10',
          weight: e['weight']?.toString() ?? '',
          setCount: (e['sets'] as List?)?.length ?? 3,
        ),
      );
    }
    if (exercises.isEmpty) exercises.add(_ExerciseDraft());
  }

  @override
  void dispose() {
    name.dispose();
    date.dispose();
    for (final e in exercises) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'Plan a gym session' : 'Edit gym session',
    ),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Session name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: date,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Date',
                suffixIcon: Icon(Icons.calendar_month),
              ),
              onTap: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(date.text) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (p != null) setState(() => date.text = dayKey(p));
              },
            ),
            const SizedBox(height: 12),
            _RepeatScheduleEditor(
              startDate: date.text,
              initial: repeatRule,
              onChanged: (rule) => repeatRule = rule,
            ),
            ...exercises.asMap().entries.map((entry) {
              final index = entry.key, e = entry.value;
              return Card(
                key: ValueKey(e),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Exercise ${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: exercises.length <= 1
                                ? null
                                : () => setState(
                                    () => exercises.removeAt(index).dispose(),
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      TextField(
                        controller: e.name,
                        decoration: const InputDecoration(
                          labelText: 'Exercise name',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: e.muscle,
                        decoration: const InputDecoration(
                          labelText: 'Muscle group',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: e.setCount,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Sets'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: e.reps,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Target reps',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: e.weight,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Target kg',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: e.notes,
                        decoration: const InputDecoration(labelText: 'Notes'),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: index == 0
                                ? null
                                : () => setState(() => _move(index, index - 1)),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            onPressed: index == exercises.length - 1
                                ? null
                                : () => setState(() => _move(index, index + 1)),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          const Text('Change exercise order'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => exercises.add(_ExerciseDraft())),
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (name.text.trim().isEmpty) return;
          final output = <Map<String, Object?>>[];
          for (final e in exercises) {
            final count = int.tryParse(e.setCount.text) ?? 0,
                reps = int.tryParse(e.reps.text) ?? 0,
                kg = double.tryParse(e.weight.text) ?? 0;
            if (e.name.text.trim().isEmpty ||
                count <= 0 ||
                reps <= 0 ||
                kg < 0) {
              continue;
            }
            output.add({
              'name': e.name.text.trim(),
              'muscle': e.muscle.text.trim(),
              'notes': e.notes.text.trim(),
              'sets': [
                for (var i = 0; i < count; i++)
                  {
                    'targetReps': reps,
                    'actualReps': null,
                    'targetKg': kg,
                    'actualKg': null,
                    'completed': false,
                  },
              ],
            });
          }
          if (output.isEmpty) return;
          Navigator.pop(
            context,
            _WorkoutPlanResult(name.text.trim(), date.text, output, repeatRule),
          );
        },
        child: const Text('Save session'),
      ),
    ],
  );
  void _move(int a, int b) {
    final v = exercises.removeAt(a);
    exercises.insert(b, v);
  }
}

Future<void> _runLogDialog(
  BuildContext context,
  TrackerController c, {
  Map<String, Object?>? existing,
}) async {
  final distance = TextEditingController(
        text: existing?['distance_km']?.toString() ?? '',
      ),
      duration = TextEditingController(),
      note = TextEditingController(text: (existing?['note'] as String?) ?? ''),
      date = TextEditingController(
        text: (existing?['date'] as String?) ?? c.selectedDate,
      );
  duration.text = existing?['duration_min']?.toString() ?? '';
  final result = await showDialog<List<String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Log a run'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: date,
            decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: distance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Distance (km)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: duration,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Duration (minutes)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, [
            date.text,
            distance.text,
            duration.text,
            note.text,
          ]),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result == null) return;
  final d = double.tryParse(result[1]), m = double.tryParse(result[2]);
  if (d == null || d <= 0 || m == null || m <= 0) {
    if (context.mounted) {
      _toast(context, 'Enter positive distance and duration.');
    }
    return;
  }
  await c.logRun(
    id: existing?['id'] as String?,
    date: result[0],
    distance: d,
    minutes: m,
    note: result[3],
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.aiConfigured,
    this.onAiStatusChanged,
  });
  final bool aiConfigured;
  final VoidCallback? onAiStatusChanged;
  @override
  Widget build(BuildContext context) {
    final c = TrackerScope.of(context);
    return PageFrame(
      title: 'Settings',
      subtitle: 'Your goals and preferences',
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Personal targets'),
              Text(
                'Height: ${fmt(c.goals.heightCm)} cm · Starting weight: ${fmt(c.goals.startKg)} kg',
              ),
              Text(
                'Target: ${fmt(c.goals.targetMinKg)}–${fmt(c.goals.targetMaxKg)} kg',
              ),
              Text(
                'Daily goals: ${fmt(c.goals.kcal)} kcal · ${fmt(c.goals.protein)} g protein',
              ),
              TextButton.icon(
                onPressed: () => _editGoals(context, c),
                icon: const Icon(Icons.edit),
                label: const Text('Edit targets'),
              ),
            ],
          ),
        ),
        SurfaceCard(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Dark theme'),
                value: c.goals.darkMode,
                onChanged: (v) => c.saveGoals(c.goals.copyWith(darkMode: v)),
              ),
              SwitchListTile(
                title: const Text('Enable AI'),
                subtitle: Text(
                  aiConfigured
                      ? 'User-triggered only'
                      : 'Add a Gemini API key in AI Setup to enable',
                ),
                value: c.goals.aiEnabled,
                onChanged: (v) => c.saveGoals(c.goals.copyWith(aiEnabled: v)),
              ),
            ],
          ),
        ),
        SurfaceCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI Setup'),
            subtitle: Text(
              aiConfigured
                  ? 'Gemini API key is configured'
                  : 'Add your Gemini API key',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AiSetupScreen(configured: aiConfigured),
                  ),
                )
                .then((_) => onAiStatusChanged?.call()),
          ),
        ),
        const SurfaceCard(
          child: Text(
            'Your diary, weight and activity stay on this device. AI sends only selected content after you tap Analyze. Open Food Facts receives only a food search query when you tap its search button. Exported backups are unencrypted files that you choose where to save.',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _export(context, c),
              icon: const Icon(Icons.backup),
              label: const Text('Backup'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _export(context, c, csv: true),
              icon: const Icon(Icons.table_view),
              label: const Text('CSV export'),
            ),
            OutlinedButton.icon(
              onPressed: () => _restore(context, c),
              icon: const Icon(Icons.restore),
              label: const Text('Restore'),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _deleteAllLocalData(context, c),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete all local data'),
          ),
        ),
      ],
    );
  }
}

class AiSetupScreen extends StatefulWidget {
  const AiSetupScreen({super.key, this.assistant, this.configured = false});
  final AiAssistant? assistant;
  final bool configured;
  @override
  State<AiSetupScreen> createState() => _AiSetupScreenState();
}

class _AiSetupScreenState extends State<AiSetupScreen> {
  AiAssistant get assistant => widget.assistant ?? AiAssistant.instance;
  final keyController = TextEditingController();
  bool configured = false;
  bool busy = false;
  bool? testSucceeded;
  String? message;
  String selectedModel = AiAssistant.defaultModelName;

  @override
  void initState() {
    super.initState();
    configured = widget.configured;
    assistant.loadKeyState().then((hasKey) {
      if (!mounted) return;
      setState(() {
        configured = hasKey;
        selectedModel = assistant.modelName;
      });
    });
  }

  @override
  void dispose() {
    keyController.dispose();
    super.dispose();
  }

  Future<void> saveKey() async {
    try {
      await assistant.saveApiKey(keyController.text);
      keyController.clear();
      if (!mounted) return;
      setState(() {
        configured = true;
        message = 'API key saved securely on this device.';
        testSucceeded = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error is ArgumentError
              ? error.message.toString()
              : 'Could not save the key.',
        );
      }
    }
  }

  Future<void> testKey() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      message = null;
      testSucceeded = null;
    });
    try {
      if (keyController.text.trim().isNotEmpty) {
        await assistant.saveApiKey(keyController.text);
      }
      await assistant.testConnection();
      if (!mounted) return;
      setState(() {
        configured = true;
        testSucceeded = true;
        message = 'Connection succeeded with $selectedModel.';
      });
      keyController.clear();
    } catch (error) {
      if (!mounted) return;
      final info = AiAssistant.failureInfo(error);
      setState(() {
        configured = assistant.configured;
        testSucceeded = false;
        message = '${info.title}. ${info.message}';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> removeKey() async {
    await assistant.removeApiKey();
    if (!mounted) return;
    setState(() {
      configured = false;
      testSucceeded = null;
      message = 'API key removed from this device.';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI Setup')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use your Gemini API key',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Create a key in Google AI Studio. Free-tier availability and limits depend on your Google project and selected model. Google receives prompts and photos only when you request AI analysis. Usage and any charges follow your Google AI Studio project.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://aistudio.google.com/apikey'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Get an API key in Google AI Studio'),
                ),
              ),
              DropdownButtonFormField<String>(
                key: const Key('gemini_model_selector'),
                initialValue: selectedModel,
                decoration: const InputDecoration(
                  labelText: 'Gemini model',
                  border: OutlineInputBorder(),
                ),
                items: AiAssistant.availableModels
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) async {
                        if (value == null) return;
                        await assistant.setModel(value);
                        if (mounted) {
                          setState(() {
                            selectedModel = value;
                            testSucceeded = null;
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('gemini_api_key_input'),
                controller: keyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(
                  labelText: 'Gemini API key',
                  hintText: 'Paste your key',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : saveKey,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save key'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : testKey,
                    icon: const Icon(Icons.network_check),
                    label: const Text('Test connection'),
                  ),
                  if (configured)
                    TextButton.icon(
                      onPressed: busy ? null : removeKey,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove key'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                configured ? 'API key configured (masked)' : 'No API key saved',
              ),
              if (testSucceeded != null)
                Text(
                  testSucceeded!
                      ? 'Last connection test succeeded'
                      : 'Last connection test failed',
                ),
              if (busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  message!,
                  style: TextStyle(
                    color: testSucceeded == false
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SurfaceCard(
          child: Text(
            'Your key is stored in encrypted device storage and is sent only in the HTTPS Gemini API request header. It is never displayed after saving. Do not share screenshots of the key before saving. AI requests are sent directly to Google; manual food logging remains available without a key or internet connection.',
          ),
        ),
      ],
    ),
  );
}

Future<void> _deleteAllLocalData(
  BuildContext context,
  TrackerController c,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete all local data?'),
      content: const Text(
        'This removes your diary, weight, custom foods, recipes, saved meals, workouts, runs and AI usage history. Built-in foods remain available.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete all'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final db = await c.db.database;
  for (final table in [
    'entries',
    'weights',
    'recipes',
    'saved_meals',
    'workout_plans',
    'workout_logs',
    'run_logs',
  ]) {
    await db.delete(table);
  }
  await db.delete('foods', where: "source = 'Custom' OR category = 'Recipe'");
  await db.update('foods', {'favourite': 0});
  await c.db.saveGoals(const AppGoals());
  await c.load();
  if (context.mounted) _toast(context, 'Local data deleted.');
}

Future<void> _editGoals(BuildContext context, TrackerController c) async {
  final old = [
    c.goals.heightCm,
    c.goals.startKg,
    c.goals.targetMinKg,
    c.goals.targetMaxKg,
    c.goals.kcal,
    c.goals.protein,
    c.goals.carbs,
    c.goals.fat,
  ];
  final fields = old
      .map((v) => TextEditingController(text: v == 0 ? '' : fmt(v, digits: 1)))
      .toList();
  final result = await showDialog<List<double?>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit targets'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            fields.length,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: fields[i],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: [
                    'Height cm',
                    'Starting weight kg',
                    'Target minimum kg',
                    'Target maximum kg',
                    'Calories/day',
                    'Protein g/day',
                    'Carbs g/day (optional)',
                    'Fat g/day (optional)',
                  ][i],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            fields
                .map(
                  (f) => f.text.trim().isEmpty ? null : double.tryParse(f.text),
                )
                .toList(),
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result == null) return;
  final v = [for (var i = 0; i < old.length; i++) result[i] ?? old[i]];
  if (v.any((x) => x < 0) || v[4] <= 0 || v[5] <= 0 || v[2] > v[3]) {
    if (context.mounted) _toast(context, 'Check the values and target range.');
    return;
  }
  await c.saveGoals(
    c.goals.copyWith(
      heightCm: v[0],
      startKg: v[1],
      targetMinKg: v[2],
      targetMaxKg: v[3],
      kcal: v[4],
      protein: v[5],
      carbs: v[6],
      fat: v[7],
    ),
  );
}

Future<void> showWeightDialog(
  BuildContext context, {
  WeightEntry? existing,
}) async {
  final c = TrackerScope.of(context);
  final field = TextEditingController(text: existing?.kg.toString() ?? ''),
      note = TextEditingController(text: existing?.note ?? '');
  final date = TextEditingController(text: existing?.date ?? c.selectedDate);
  final result = await showDialog<List<String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Log weight'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: field,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Weight (kg)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Optional note'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: date,
            decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, [field.text, note.text, date.text]),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result == null) return;
  final kg = double.tryParse(result[0]);
  if (kg == null || kg <= 0) {
    if (context.mounted) _toast(context, 'Enter a valid weight.');
    return;
  }
  await c.addWeight(
    WeightEntry(id: existing?.id, date: result[2], kg: kg, note: result[1]),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

Future<String?> _textPrompt(
  BuildContext context,
  String title,
  String hint, {
  bool multiline = false,
  bool allowEmpty = false,
  bool autofocus = false,
  String initial = '',
}) async {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      hint: hint,
      multiline: multiline,
      allowEmpty: allowEmpty,
      autofocus: autofocus,
      initial: initial,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.hint,
    required this.multiline,
    required this.allowEmpty,
    required this.autofocus,
    required this.initial,
  });

  final String title;
  final String hint;
  final bool multiline;
  final bool allowEmpty;
  final bool autofocus;
  final String initial;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final controller = TextEditingController();
  bool showEmptyError = false;

  @override
  void initState() {
    super.initState();
    controller.text = widget.initial;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: widget.autofocus,
      minLines: widget.multiline ? 3 : 1,
      maxLines: widget.multiline ? 6 : 1,
      decoration: InputDecoration(
        hintText: widget.hint,
        helperText: !widget.allowEmpty
            ? 'Type or dictate a description.'
            : null,
        errorText: showEmptyError ? 'Enter a description to analyze.' : null,
      ),
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) {
        if (showEmptyError) setState(() => showEmptyError = false);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = controller.text.trim();
          if (!widget.allowEmpty && value.isEmpty) {
            setState(() => showEmptyError = true);
            return;
          }
          Navigator.pop(context, value);
        },
        child: Text(widget.allowEmpty ? 'Continue' : 'Analyze'),
      ),
    ],
  );
}

void _toast(BuildContext context, String value) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(value)));
}

class CalorieCompanionApp extends StatefulWidget {
  const CalorieCompanionApp({super.key});
  @override
  State<CalorieCompanionApp> createState() => _CalorieCompanionAppState();
}

class _CalorieCompanionAppState extends State<CalorieCompanionApp> {
  final controller = TrackerController(LocalDatabase.instance);
  bool aiConfigured = false;
  @override
  void initState() {
    super.initState();
    controller.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AiAssistant.instance
          .loadKeyState()
          .then((configured) {
            if (mounted) setState(() => aiConfigured = configured);
          })
          .catchError((Object _) {
            if (mounted) setState(() => aiConfigured = false);
          });
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TrackerScope(
    controller: controller,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NutriTrack',
        themeMode: controller.goals.darkMode ? ThemeMode.dark : ThemeMode.light,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: controller.ready
            ? MainShell(
                aiConfigured: aiConfigured,
                onAiStatusChanged: _refreshAiConfiguration,
              )
            : const _LoadingScreen(),
      ),
    ),
  );

  void _refreshAiConfiguration() {
    if (mounted) setState(() => aiConfigured = AiAssistant.instance.configured);
  }
}

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff08786c),
    brightness: brightness,
    surface: dark ? const Color(0xff121816) : const Color(0xfff4f7f5),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Roboto',
    textTheme: ThemeData(brightness: brightness).textTheme.copyWith(
      headlineMedium: ThemeData(brightness: brightness).textTheme.headlineMedium
          ?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
          ),
      titleLarge: ThemeData(brightness: brightness).textTheme.titleLarge
          ?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
      titleMedium: ThemeData(brightness: brightness).textTheme.titleMedium
          ?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      bodyLarge: ThemeData(brightness: brightness).textTheme.bodyLarge
          ?.copyWith(fontSize: 16),
      bodyMedium: ThemeData(brightness: brightness).textTheme.bodyMedium
          ?.copyWith(fontSize: 14),
      bodySmall: ThemeData(brightness: brightness).textTheme.bodySmall
          ?.copyWith(fontSize: 12),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xff202725) : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .34)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .55),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xff171c1b) : scheme.surface,
      indicatorColor: scheme.primaryContainer,
    ),
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.aiConfigured,
    required this.onAiStatusChanged,
  });
  final bool aiConfigured;
  final VoidCallback onAiStatusChanged;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onNavigate: (i) => setState(() => index = i)),
      FoodScreen(aiConfigured: widget.aiConfigured),
      const ProgressScreen(),
      const ActivityScreen(),
      SettingsScreen(
        aiConfigured: widget.aiConfigured,
        onAiStatusChanged: widget.onAiStatusChanged,
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu),
            label: 'Food',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.trailing,
    this.scroll = true,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;
  final bool scroll;
  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 22),
        ...children.map(
          (e) => Padding(padding: const EdgeInsets.only(bottom: 14), child: e),
        ),
        const SizedBox(height: 14),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: scroll ? SingleChildScrollView(child: content) : content,
        ),
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

String fmt(double x, {int digits = 0}) => x.toStringAsFixed(digits);
String todayLabel(String key) {
  final d = DateTime.parse(key);
  final now = DateTime.now();
  if (dayKey(d) == dayKey(now)) return 'Today';
  if (dayKey(d) == dayKey(now.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  return '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]}, ${d.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
}

class NutriTrackMark extends StatelessWidget {
  const NutriTrackMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: Image.asset(
        'assets/branding/nutritrack_app_icon.png',
        fit: BoxFit.cover,
      ),
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;
  @override
  Widget build(BuildContext context) {
    final c = TrackerScope.of(context);
    final totals = c.dayTotals;
    final remaining = c.goals.kcal - totals.kcal;
    final last = c.latestWeight;
    return PageFrame(
      title: 'Today',
      subtitle: todayLabel(c.selectedDate),
      trailing: IconButton(
        onPressed: () => _pickDay(context, c),
        icon: const Icon(Icons.calendar_month_rounded),
      ),
      children: [
        Row(
          children: [
            const NutriTrackMark(size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NutriTrack',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Simple tracking. Healthier days.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Daily energy',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${fmt(totals.kcal)} / ${fmt(c.goals.kcal)} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (totals.kcal / c.goals.kcal).clamp(0, 1),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${fmt(remaining)} kcal remaining',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: remaining < 0
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                remaining < 0
                    ? 'You are above today’s target.'
                    : 'A flexible guide for your day.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        WeeklyCaloriesSection(controller: c, dailyTarget: c.goals.kcal),
        Row(
          children: [
            Expanded(
              child: MacroCard(
                label: 'Protein',
                amount: totals.protein,
                target: c.goals.protein,
                color: const Color(0xff478679),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MacroCard(
                label: 'Carbs',
                amount: totals.carbs,
                target: c.goals.carbs,
                color: const Color(0xffd39a4a),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MacroCard(
                label: 'Fat',
                amount: totals.fat,
                target: c.goals.fat,
                color: const Color(0xffb86b72),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: QuickAction(
                icon: Icons.add_rounded,
                label: 'Log food',
                onTap: () => onNavigate(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: QuickAction(
                icon: Icons.monitor_weight_outlined,
                label: 'Log weight',
                onTap: () => showWeightDialog(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: QuickAction(
                icon: Icons.fitness_center_rounded,
                label: 'Activity',
                onTap: () => onNavigate(3),
              ),
            ),
          ],
        ),
        SurfaceCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.monitor_weight_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Weight',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      last == null
                          ? 'Add your first measurement'
                          : '${fmt(last.kg, digits: 1)} kg · ${todayLabel(last.date)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                '${fmt(c.goals.targetMinKg, digits: 0)}–${fmt(c.goals.targetMaxKg, digits: 0)} kg goal',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        const SectionTitle('Today’s diary'),
        if (c.entries.isEmpty)
          SurfaceCard(
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.restaurant, size: 32),
                  const SizedBox(height: 8),
                  const Text('Your diary is ready'),
                  const SizedBox(height: 5),
                  const Text('Add food to see your day take shape.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => onNavigate(1),
                    icon: const Icon(Icons.add),
                    label: const Text('Add a meal'),
                  ),
                ],
              ),
            ),
          )
        else
          ...['Breakfast', 'Lunch', 'Dinner', 'Snack'].map((meal) {
            final items = c.entries.where((e) => e.meal == meal).toList();
            if (items.isEmpty) return const SizedBox.shrink();
            final sum = items.fold(const Nutrition(), (a, e) => a + e.total);
            return SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meal,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('${fmt(sum.kcal)} kcal'),
                    ],
                  ),
                  const Divider(height: 22),
                  ...items.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${fmt(e.quantity, digits: 1)} × ${e.name}',
                            ),
                          ),
                          Text('${fmt(e.total.kcal)} kcal'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        const SectionTitle('This week'),
        SurfaceCard(
          child: Row(
            children: [
              Expanded(
                child: _miniMetric(
                  context,
                  '7-day weight avg',
                  c.sevenDayAverage == null
                      ? '—'
                      : '${fmt(c.sevenDayAverage!, digits: 1)} kg',
                  Icons.show_chart,
                ),
              ),
              Expanded(
                child: _miniMetric(
                  context,
                  'Workouts',
                  '${c.workoutPlans.where((p) => (p['completed'] as num?) == 1).length} complete',
                  Icons.fitness_center,
                ),
              ),
              Expanded(
                child: _miniMetric(
                  context,
                  'Runs',
                  '${c.runLogs.length} logged',
                  Icons.directions_run,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniMetric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 7),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class MacroCard extends StatelessWidget {
  const MacroCard({
    super.key,
    required this.label,
    required this.amount,
    required this.target,
    required this.color,
  });
  final String label;
  final double amount, target;
  final Color color;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 9),
        Text(
          '${fmt(amount)} g',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: target > 0 ? (amount / target).clamp(0, 1) : 0,
            minHeight: 5,
            color: color,
          ),
        ),
        if (target > 0)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              'of ${fmt(target)} g',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
      ],
    ),
  );
}

class WeeklyCaloriesSection extends StatefulWidget {
  const WeeklyCaloriesSection({
    super.key,
    required this.controller,
    required this.dailyTarget,
  });
  final TrackerController controller;
  final double dailyTarget;

  @override
  State<WeeklyCaloriesSection> createState() => _WeeklyCaloriesSectionState();
}

class _WeeklyCaloriesSectionState extends State<WeeklyCaloriesSection> {
  late DateTime weekStart;
  late Future<List<FoodEntry>> entries;

  @override
  void initState() {
    super.initState();
    weekStart = mondayOfWeek(DateTime.now());
    entries = _load();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant WeeklyCaloriesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
      _refresh();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  Future<List<FoodEntry>> _load() => widget.controller.entriesBetween(
    dayKey(weekStart),
    dayKey(weekStart.add(const Duration(days: 6))),
  );

  void _refresh() {
    if (mounted) setState(() => entries = _load());
  }

  void _shift(int days) {
    setState(() {
      weekStart = weekStart.add(Duration(days: days));
      entries = _load();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<FoodEntry>>(
    future: entries,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SurfaceCard(
          child: Text('Weekly calories could not be loaded: ${snapshot.error}'),
        );
      }
      if (!snapshot.hasData) {
        return const SurfaceCard(
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final all = snapshot.data!;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final currentWeek = mondayOfWeek(today);
      final summary = summarizeWeeklyCalories(
        entries: all,
        monday: weekStart,
        today: today,
        dailyTarget: widget.dailyTarget,
      );
      final labels = <String>[];
      for (var i = 0; i < 7; i++) {
        labels.add(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i]);
      }
      final range =
          '${_shortDate(weekStart)} – ${_shortDate(weekStart.add(const Duration(days: 6)))}';
      final maxValue = [
        widget.dailyTarget,
        ...summary.days.map((day) => day.kcal),
      ].reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);
      return SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Weekly calories',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous week',
                  onPressed: () => _shift(-7),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Current week',
                  onPressed: weekStart == currentWeek
                      ? null
                      : () => setState(() {
                          weekStart = currentWeek;
                          entries = _load();
                        }),
                  icon: const Icon(Icons.today_outlined),
                ),
                IconButton(
                  tooltip: 'Next week',
                  onPressed: weekStart.isBefore(currentWeek)
                      ? () => _shift(7)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Text(
              weekStart == currentWeek ? 'This week · $range' : range,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 5),
            Text(
              'Target: ${fmt(widget.dailyTarget)} kcal each day',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 137,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    summary.days[i].isFuture
                                        ? '·'
                                        : summary.days[i].needsReview
                                        ? 'Review'
                                        : summary.days[i].hasEntries
                                        ? fmt(summary.days[i].kcal)
                                        : '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: FractionallySizedBox(
                                        heightFactor:
                                            summary.days[i].hasLoggedCalories &&
                                                summary.days[i].kcal > 0
                                            ? (summary.days[i].kcal / maxValue)
                                                  .clamp(.025, 1)
                                            : .012,
                                        widthFactor: .68,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color:
                                                summary
                                                    .days[i]
                                                    .hasLoggedCalories
                                                ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .outlineVariant,
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(5),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    labels[i],
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom:
                        31 + (widget.dailyTarget / maxValue * 74).clamp(0, 74),
                    child: IgnorePointer(
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Theme.of(context).colorScheme.tertiary,
                              thickness: 1.5,
                            ),
                          ),
                          Text(
                            ' target ',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Logged food only · days with no entries are unknown, not zero.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 5,
              children: [
                Text('Week total ${fmt(summary.totalKcal)} kcal'),
                Text(
                  summary.averageKcal == null
                      ? 'Average —'
                      : 'Average ${fmt(summary.averageKcal!)} kcal across ${summary.loggedDayCount} logged day${summary.loggedDayCount == 1 ? '' : 's'}',
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Below ${summary.belowTarget} · at ${summary.atTarget} · above ${summary.aboveTarget} target (${summary.loggedDayCount} days with entries)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              summary.loggedDayCount == 0
                  ? 'No target comparison yet; log food to compare logged days.'
                  : 'Logged ${summary.differenceFromTarget >= 0 ? '+' : ''}${fmt(summary.differenceFromTarget)} kcal vs target for ${summary.loggedDayCount} logged days (${fmt(summary.targetForLoggedDays)} kcal).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    },
  );

  String _shortDate(DateTime date) => '${date.day} ${_month(date.month)}';
  String _month(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];
}

class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

Future<void> _pickDay(BuildContext context, TrackerController c) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime.parse(c.selectedDate),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (picked != null) await c.selectDate(dayKey(picked));
}

class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, required this.aiConfigured, this.aiClient});
  final bool aiConfigured;
  final AiClient? aiClient;
  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  final query = TextEditingController();
  final search = FoodSearchService();
  String tab = 'Search';
  bool loadingRemote = false;
  bool remoteSearched = false;
  bool addingSavedMeal = false;
  List<Food> remote = [];
  String? remoteError;
  String? failedAiDraft;
  int imagePickerPreparationMs = 0;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TrackerScope.of(context);
    final q = query.text.toLowerCase().trim();
    final matches = c.foods
        .where(
          (f) =>
              q.isEmpty ||
              f.name.toLowerCase().contains(q) ||
              f.category.toLowerCase().contains(q),
        )
        .toList();
    return PageFrame(
      title: 'Food diary',
      subtitle: todayLabel(c.selectedDate),
      trailing: IconButton(
        onPressed: () => _pickDay(context, c),
        icon: const Icon(Icons.calendar_month_outlined),
      ),
      children: [
        if (c.nutritionEntriesNeedingReview.isNotEmpty)
          SurfaceCard(
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: const Text('Some past nutrition entries need review'),
              subtitle: Text(
                '${c.nutritionEntriesNeedingReview.length} entries were left unchanged because they could not be safely repaired: ${c.nutritionEntriesNeedingReview.map((entry) => '${entry.name} (${entry.date})').join(', ')}. They are excluded from calculated totals until reviewed. Correct them in the diary or delete and re-log.',
              ),
            ),
          ),
        _aiAssistant(context, c),
        _foodQuickActions(context, c),
        _dailyDiary(context, c),
        TextField(
          controller: query,
          onChanged: (_) => setState(() {
            remote = [];
            remoteSearched = false;
            remoteError = null;
          }),
          decoration: InputDecoration(
            hintText: 'Search foods, dishes, recipes',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (query.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(query.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
                IconButton(
                  tooltip: 'Create a custom food',
                  onPressed: () => _createFood(context),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in [
                'Search',
                'Recent',
                'Favourites',
                'Breakfast',
                'Lunch',
                'Dinner',
                'Snack',
                'Saved',
                'Saved favourites',
              ]) ...[
                if (t != 'Search') const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(t),
                  selected: tab == t,
                  onSelected: (_) => setState(() => tab = t),
                ),
              ],
            ],
          ),
        ),
        if (tab == 'Saved' || tab == 'Saved favourites')
          _savedMeals(
            context,
            c,
            query: q,
            favouritesOnly: tab == 'Saved favourites',
          )
        else if (tab == 'Recent')
          _recentFoods(context, c).isEmpty
              ? const _EmptyCard(
                  icon: Icons.history,
                  title: 'No recent foods yet',
                  text: 'Foods you log will appear here for quick access.',
                )
              : Column(
                  children: _recentFoods(
                    context,
                    c,
                  ).map((f) => _foodRow(context, c, f)).toList(),
                )
        else if (tab == 'Favourites')
          c.foods.where((f) => f.favourite).isEmpty
              ? const _EmptyCard(
                  icon: Icons.favorite_border,
                  title: 'No favourites yet',
                  text: 'Tap the heart on a food to keep it close at hand.',
                )
              : Column(
                  children: c.foods
                      .where((f) => f.favourite)
                      .map((f) => _foodRow(context, c, f))
                      .toList(),
                )
        else if (tab != 'Search')
          _diaryMeal(context, c, tab)
        else ...[
          if (q.isNotEmpty && matches.isEmpty) ...[
            _remoteSearchButton(context, q),
            if (remoteSearched && remote.isEmpty)
              OutlinedButton.icon(
                onPressed: () => _unknownFoodAi(context, c, q),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Estimate this food with AI'),
              ),
          ],
          if (remoteError != null)
            Text(
              remoteError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ...matches.take(30).map((f) => _foodRow(context, c, f)),
          ...remote.map((f) => _foodRow(context, c, f, remoteFood: true)),
          if (matches.isEmpty && remote.isEmpty && q.isEmpty)
            const _EmptyCard(
              icon: Icons.search,
              title: 'Search your food library',
              text: 'Try an Indian staple, a favourite, or a packaged food.',
            ),
        ],
      ],
    );
  }

  Widget _foodQuickActions(BuildContext context, TrackerController c) =>
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick actions',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _quickFoodAction(
              context,
              icon: Icons.edit_note_rounded,
              title: 'Add food manually',
              description: 'Enter known nutrition without AI.',
              onTap: () => _createFood(context),
            ),
            _quickFoodAction(
              context,
              icon: Icons.menu_book_outlined,
              title: 'New recipe',
              description: 'Save ingredients and servings as a reusable food.',
              onTap: () => _createRecipe(context),
            ),
            _quickFoodAction(
              context,
              icon: Icons.bookmark_add_outlined,
              title: 'Save today’s meal',
              description:
                  'Save today’s logged entries as a reusable template.',
              onTap: () => _saveMeal(context, c),
            ),
          ],
        ),
      );

  Widget _quickFoodAction(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(description),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  Widget _foodRow(
    BuildContext context,
    TrackerController c,
    Food f, {
    bool remoteFood = false,
  }) => Column(
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minVerticalPadding: 8,
        horizontalTitleGap: 12,
        title: Text(
          f.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Serving ${fmt(f.serving, digits: 1)} ${f.unit} · ${fmt(f.nutrition.kcal)} kcal · P ${fmt(f.nutrition.protein, digits: 1)} / C ${fmt(f.nutrition.carbs, digits: 1)} / F ${fmt(f.nutrition.fat, digits: 1)} g',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                f.source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: SizedBox(
          width: 96,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 48,
                ),
                padding: EdgeInsets.zero,
                tooltip: f.favourite ? 'Unfavourite' : 'Favourite',
                onPressed: remoteFood ? null : () => c.toggleFavourite(f),
                icon: Icon(
                  f.favourite ? Icons.favorite : Icons.favorite_border,
                  color: f.favourite
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 48,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'Log ${f.name}',
                onPressed: () => _logFood(context, c, f),
                icon: Icon(
                  Icons.add_circle_rounded,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
      Divider(
        height: 1,
        indent: 8,
        endIndent: 8,
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .7),
      ),
    ],
  );

  Widget _aiAssistant(BuildContext context, TrackerController c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionTitle('AI food assistant'),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Review before saving',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'AI is optional. Check estimates before they enter your diary.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (failedAiDraft != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Manual fallback · nothing was saved'),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Dismiss',
                          onPressed: () => setState(() => failedAiDraft = null),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    SelectableText(failedAiDraft!),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 8) / 2;
                final actions = <(String, IconData, VoidCallback)>[
                  (
                    'Describe a meal',
                    Icons.edit_note,
                    () => _textAi(context, c),
                  ),
                  (
                    'Photo + context',
                    Icons.add_a_photo_outlined,
                    () => _photoAi(context, c),
                  ),
                  (
                    'Scan nutrition facts',
                    Icons.document_scanner_outlined,
                    () => _photoAi(context, c, label: true),
                  ),
                  (
                    'Review today',
                    Icons.insights_outlined,
                    () => _reviewAi(context, c),
                  ),
                ];
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      SizedBox(
                        width: width,
                        height: 48,
                        child: i == 0
                            ? FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                onPressed: actions[i].$3,
                                icon: Icon(actions[i].$2, size: 19),
                                label: Text(
                                  actions[i].$1,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            : OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                onPressed: actions[i].$3,
                                icon: Icon(actions[i].$2, size: 19),
                                label: Text(
                                  actions[i].$1,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                      ),
                  ],
                );
              },
            ),
            if (!widget.aiConfigured)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Enable AI in Settings and add your Gemini API key. Manual logging works offline.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _dailyDiary(BuildContext context, TrackerController c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionTitle('Diary · ${todayLabel(c.selectedDate)}'),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${fmt(c.dayTotals.kcal)} kcal  ·  P ${fmt(c.dayTotals.protein)} g  ·  C ${fmt(c.dayTotals.carbs)} g  ·  F ${fmt(c.dayTotals.fat)} g',
              key: const ValueKey('food-day-totals'),
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final meal in ['Breakfast', 'Lunch', 'Dinner', 'Snack'])
              _diaryMeal(context, c, meal),
          ],
        ),
      ),
    ],
  );

  List<Food> _recentFoods(BuildContext context, TrackerController c) {
    final seen = <String>{};
    final result = <Food>[];
    for (final entry in c.historyEntries) {
      final key = entry.foodId ?? entry.name.toLowerCase();
      if (!seen.add(key)) continue;
      Food? sourceFood;
      for (final food in c.foods) {
        if (food.id == entry.foodId) {
          sourceFood = food;
          break;
        }
      }
      final massBased = const {'g', 'ml'}.contains(entry.unit.toLowerCase());
      final recentServing = entry.originalQuantity == null
          ? (entry.nutritionBasis == 'per100'
                ? 100.0
                : sourceFood?.serving ?? 1.0)
          : massBased
          ? 100.0
          : 1.0;
      final recentNutrition = entry.originalQuantity == null
          ? entry.baseNutrition
          : entry.baseNutrition.scale(
              quantityRatio(
                recentServing,
                entry.unit,
                entry.originalQuantity!,
                entry.originalUnit ?? entry.unit,
              ),
            );
      result.add(
        Food(
          id: entry.foodId,
          name: entry.name,
          serving: recentServing,
          unit: entry.unit,
          nutrition: recentNutrition,
          source: entry.source,
        ),
      );
      if (result.length >= 15) break;
    }
    return result;
  }

  Widget _remoteSearchButton(BuildContext context, String q) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      onPressed: loadingRemote
          ? null
          : () async {
              setState(() => loadingRemote = true);
              try {
                final result = await search.searchOpenFoodFacts(q);
                if (mounted) {
                  setState(() {
                    remote = result;
                    remoteSearched = true;
                  });
                }
              } catch (e) {
                if (mounted) setState(() => remoteError = '$e');
              } finally {
                if (mounted) setState(() => loadingRemote = false);
              }
            },
      icon: loadingRemote
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.public),
      label: Text(loadingRemote ? 'Searching…' : 'Search Open Food Facts'),
    ),
  );
  Widget _diaryMeal(BuildContext context, TrackerController c, String meal) {
    final list = c.entries.where((e) => e.meal == meal).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(meal),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'No $meal entries',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          ...list.map((e) => _foodDiaryEntry(context, c, e)),
      ],
    );
  }

  Widget _foodDiaryEntry(
    BuildContext context,
    TrackerController c,
    FoodEntry entry,
  ) {
    final usable = usableFoodEntryNutrition(entry);
    final isAi =
        entry.source.toLowerCase().contains('ai') ||
        entry.source.toLowerCase().contains('label');
    final confidence = RegExp(
      r'\b(low|medium|high)\s+confidence\b',
      caseSensitive: false,
    ).firstMatch(entry.source)?.group(1);
    final detailLabel = isAi ? 'Estimation details' : 'Entry details';

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${fmt(entry.quantity, digits: 1)} ${entry.unit}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    usable ? '${fmt(entry.total.kcal)} kcal' : 'Review needed',
                    key: ValueKey('food-kcal-${entry.id}'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (!usable)
                    Text(
                      'Nutrition needs review',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              PopupMenuButton<String>(
                tooltip: 'More actions for ${entry.name}',
                onSelected: (value) async {
                  if (value == 'delete') await c.deleteEntry(entry.id);
                  if (value == 'reestimate' && context.mounted) {
                    await _reestimateEntry(context, c, entry);
                  }
                },
                itemBuilder: (_) => [
                  if (isAi)
                    const PopupMenuItem(
                      value: 'reestimate',
                      child: Text('Re-estimate with AI'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _macroTile(
                context,
                'Protein',
                usable ? fmt(entry.total.protein, digits: 1) : '—',
                'g',
              ),
              const SizedBox(width: 7),
              _macroTile(
                context,
                'Carbs',
                usable ? fmt(entry.total.carbs, digits: 1) : '—',
                'g',
              ),
              const SizedBox(width: 7),
              _macroTile(
                context,
                'Fat',
                usable ? fmt(entry.total.fat, digits: 1) : '—',
                'g',
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              TextButton.icon(
                key: ValueKey('edit-food-${entry.id}'),
                onPressed: () => _editEntry(context, c, entry),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Edit'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              const Spacer(),
              Text(
                isAi
                    ? (entry.source.toLowerCase().contains('label')
                          ? 'Label'
                          : 'AI estimate')
                    : 'Manual / local',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          if (entry.source.isNotEmpty || entry.note.trim().isNotEmpty)
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: ValueKey('food-details-${entry.id}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                visualDensity: VisualDensity.compact,
                title: Text(detailLabel),
                children: [
                  if (entry.source.isNotEmpty)
                    _entryDetailLine('Source', entry.source),
                  if (confidence != null)
                    _entryDetailLine('Confidence', confidence),
                  if (entry.referenceNutrition case final reference?)
                    _entryDetailLine(
                      'Label values',
                      '${fmt(reference.kcal)} kcal, P ${fmt(reference.protein, digits: 1)} g, C ${fmt(reference.carbs, digits: 1)} g, F ${fmt(reference.fat, digits: 1)} g per ${entry.referenceQuantity == null ? 'reference' : '${fmt(entry.referenceQuantity!, digits: 1)} ${entry.referenceUnit ?? ''}'}',
                    ),
                  if (entry.note.trim().isNotEmpty)
                    _entryDetailLine(
                      isAi ? 'Saved notes / context' : 'Saved note',
                      entry.note,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _macroTile(
    BuildContext context,
    String label,
    String value,
    String unit,
  ) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          Text(
            '$value $unit',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );

  Widget _entryDetailLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  Future<void> _editEntry(
    BuildContext context,
    TrackerController c,
    FoodEntry entry,
  ) async {
    final wasLegacy = entry.originalQuantity == null;
    final food = Food(
      id: entry.foodId,
      name: entry.name,
      serving: 1,
      unit: entry.unit,
      nutrition: wasLegacy ? entry.total : entry.baseNutrition,
      source: entry.source,
    );
    final result = await showDialog<_LogResult>(
      context: context,
      builder: (_) => _LogFoodDialog(
        food: food,
        initialQuantity: entry.quantity,
        initialMeal: entry.meal,
        initialNote: entry.note,
        initialNutrition: entry.total,
        allowNutritionEdit: true,
      ),
    );
    if (result == null) return;
    final correctedNutrition = result.nutrition;
    final nutritionChanged =
        correctedNutrition != null &&
        (correctedNutrition.kcal != entry.total.kcal ||
            correctedNutrition.protein != entry.total.protein ||
            correctedNutrition.carbs != entry.total.carbs ||
            correctedNutrition.fat != entry.total.fat);
    await c.addEntry(
      FoodEntry(
        id: entry.id,
        foodId: entry.foodId,
        name: entry.name,
        date: entry.date,
        meal: result.meal,
        quantity: result.quantity,
        unit: entry.unit,
        baseNutrition: nutritionChanged
            ? correctedNutrition
            : wasLegacy
            ? entry.total
            : entry.baseNutrition,
        nutritionBasis: 'portion',
        originalQuantity: nutritionChanged
            ? result.quantity
            : wasLegacy
            ? entry.quantity
            : entry.originalQuantity,
        originalUnit: entry.originalUnit ?? entry.unit,
        referenceQuantity: entry.referenceQuantity,
        referenceUnit: entry.referenceUnit,
        referenceNutrition: entry.referenceNutrition,
        note: result.note,
        source: entry.source,
      ),
    );
  }

  Future<void> _reestimateEntry(
    BuildContext context,
    TrackerController c,
    FoodEntry entry,
  ) async {
    final details = await _textPrompt(
      context,
      'Re-estimate ${entry.name}',
      'Describe changed ingredients, preparation, or amount eaten',
      initial:
          '${entry.name}, ${fmt(entry.quantity, digits: 2)} ${entry.unit}. ${entry.note}'
              .trim(),
      multiline: true,
      autofocus: true,
    );
    if (details == null || details.trim().isEmpty || !context.mounted) return;
    await _runAi(context, c, workflow: 'meal description', text: details);
  }

  Widget _savedMeals(
    BuildContext context,
    TrackerController c, {
    required String query,
    required bool favouritesOnly,
  }) {
    final meals = c.savedMeals.where((meal) {
      final name = (meal['name'] as String).toLowerCase();
      return name.contains(query) &&
          (!favouritesOnly || (meal['favourite'] as num? ?? 0) == 1);
    }).toList();
    if (meals.isEmpty) {
      return const _EmptyCard(
        icon: Icons.bookmark_border,
        title: 'No saved meals yet',
        text: 'Save a meal to reuse it quickly. Favourites appear in Saved favourites.',
      );
    }
    return Column(
      children: meals
          .map(
            (m) => _SavedMealCard(
              meal: m,
              busy: addingSavedMeal,
              onFavourite: () => c.toggleSavedMealFavourite(m),
              onEdit: () => _editSavedMeal(context, c, m),
              onDelete: () => _deleteSavedMeal(context, c, m),
              onAdd: () => _addSavedMeal(context, c, m),
            ),
          )
          .toList(),
    );
  }

  Future<void> _editSavedMeal(
    BuildContext context,
    TrackerController c,
    Map<String, Object?> meal,
  ) async {
    final rows = (jsonDecode(meal['data'] as String) as List)
        .map((row) => FoodEntry.fromMap(Map<String, Object?>.from(row as Map)))
        .toList();
    final edited = await showDialog<_SavedMealEdit>(
      context: context,
      builder: (_) =>
          _SavedMealEditDialog(name: meal['name'] as String, items: rows),
    );
    if (edited != null) {
      await c.updateSavedMeal(
        id: meal['id'] as String,
        name: edited.name,
        items: edited.items,
      );
    }
  }

  Future<void> _deleteSavedMeal(
    BuildContext context,
    TrackerController c,
    Map<String, Object?> meal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved meal?'),
        content: Text(
          '“${meal['name']}” will be removed. Existing diary entries will stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await c.deleteSavedMeal(meal['id'] as String);
  }

  Future<void> _addSavedMeal(
    BuildContext context,
    TrackerController c,
    Map<String, Object?> meal,
  ) async {
    if (addingSavedMeal) return;
    final multiplier = await _portionMultiplier(
      context,
      meal['name'] as String,
    );
    if (multiplier == null || !context.mounted) return;
    setState(() => addingSavedMeal = true);
    try {
      final rows = (jsonDecode(meal['data'] as String) as List)
          .map(
            (row) => FoodEntry.fromMap(Map<String, Object?>.from(row as Map)),
          )
          .where(usableFoodEntryNutrition);
      final snapshots = savedMealDiaryEntries(
        rows.toList(),
        date: c.selectedDate,
        portions: multiplier,
      );
      for (final item in snapshots) {
        await c.addEntry(item);
      }
      if (context.mounted) {
        _toast(context, 'Saved meal added to ${c.selectedDate}');
      }
    } finally {
      if (mounted) setState(() => addingSavedMeal = false);
    }
  }

  Future<double?> _portionMultiplier(
    BuildContext context,
    String mealName,
  ) async {
    final controller = TextEditingController(text: '1');
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add $mealName'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Portions',
            helperText: 'Food quantities and nutrition scale by this amount.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null ||
                  !value.isFinite ||
                  value <= 0 ||
                  value > 20) {
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: const Text('Add to diary'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _logFood(
    BuildContext context,
    TrackerController c,
    Food food, {
    double? initialQuantity,
  }) async {
    final result = await showDialog<_LogResult>(
      context: context,
      builder: (_) =>
          _LogFoodDialog(food: food, initialQuantity: initialQuantity),
    );
    if (result == null) return;
    await c.addEntry(
      FoodEntry(
        foodId: food.id,
        name: food.name,
        date: c.selectedDate,
        meal: result.meal,
        quantity: result.quantity,
        unit: food.unit,
        baseNutrition: food.nutrition.scale(
          quantityRatio(result.quantity, food.unit, food.serving, food.unit),
        ),
        nutritionBasis: 'portion',
        originalQuantity: result.quantity,
        originalUnit: food.unit,
        note: result.note,
        source: food.source,
      ),
    );
    if (context.mounted) {
      _toast(context, 'Added to ${result.meal.toLowerCase()}');
    }
  }

  Future<void> _createFood(BuildContext context) async {
    final input = await showDialog<_ManualFoodInput>(
      context: context,
      builder: (_) => const _FoodEditDialog(),
    );
    if (input != null && context.mounted) {
      final c = TrackerScope.of(context);
      final existing = c.foods.where(
        (food) =>
            food.source == 'Custom' &&
            food.name.toLowerCase() == input.food.name.toLowerCase(),
      );
      var foodToSave = input.food;
      if (existing.isNotEmpty) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Update custom food?'),
            content: Text(
              '“${input.food.name}” is already in your food library. Replace its reusable nutrition values? Previously logged entries will remain unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Update food'),
              ),
            ],
          ),
        );
        if (!context.mounted || replace != true) return;
        final previous = existing.first;
        foodToSave = Food(
          id: previous.id,
          name: input.food.name,
          serving: input.food.serving,
          unit: input.food.unit,
          nutrition: input.food.nutrition,
          category: input.food.category,
          source: input.food.source,
          favourite: previous.favourite,
          nutritionBasis: input.food.nutritionBasis,
          referenceQuantity: input.food.referenceQuantity,
        );
      }
      await c.upsertFood(foodToSave);
      if (context.mounted) {
        await _logFood(context, c, foodToSave, initialQuantity: input.quantity);
      }
    }
  }

  Future<void> _createRecipe(BuildContext context) async {
    final c = TrackerScope.of(context);
    final value = await showDialog<_RecipeInput>(
      context: context,
      builder: (_) => _RecipeDialog(foods: c.foods),
    );
    if (!context.mounted) return;
    if (value != null) {
      final duplicate = c.recipes.where(
        (recipe) =>
            (recipe['name'] as String).toLowerCase() ==
            value.name.toLowerCase(),
      );
      if (duplicate.isNotEmpty) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Update recipe?'),
            content: Text(
              'A recipe named “${value.name}” already exists. Replace its ingredients and serving nutrition? Existing diary entries will remain unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Update recipe'),
              ),
            ],
          ),
        );
        if (!context.mounted || replace != true) return;
      }
      await c.addRecipe(value.name, value.servings, value.ingredients);
      if (context.mounted) _toast(context, 'Recipe saved to your food library');
    }
  }

  Future<void> _saveMeal(BuildContext context, TrackerController c) async {
    if (c.entries.isEmpty) {
      _toast(context, 'Add food before saving a meal.');
      return;
    }
    final name = await _textPrompt(
      context,
      'Save selected day as a meal',
      'This stores the food entries currently shown for ${c.selectedDate} as a reusable snapshot.',
    );
    if (!context.mounted) return;
    if (name != null && name.trim().isNotEmpty) {
      final duplicate = c.savedMeals.where(
        (meal) =>
            (meal['name'] as String).toLowerCase() == name.trim().toLowerCase(),
      );
      if (duplicate.isNotEmpty) {
        final update = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Update saved meal?'),
            content: Text(
              'A saved meal named “${name.trim()}” already exists. Replace its template with the selected day’s entries? Historical diary entries will remain unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Update template'),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        if (update != true) return;
      }
      await c.saveMeal(name, c.entries);
    }
  }

  Future<void> _textAi(BuildContext context, TrackerController c) async {
    final text = await _textPrompt(
      context,
      'Describe your meal',
      'For example: two rotis, a bowl of dal and a teaspoon of ghee',
      multiline: true,
      autofocus: true,
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    await _runAi(context, c, workflow: 'meal description', text: text);
  }

  Future<void> _unknownFoodAi(
    BuildContext context,
    TrackerController c,
    String name,
  ) async {
    final details = await _textPrompt(
      context,
      'Estimate an unknown food',
      'Optional serving size or preparation details',
      multiline: true,
      allowEmpty: true,
      autofocus: true,
    );
    if (details == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ask AI for an estimate?'),
        content: Text(
          'Food name: $name\nServing details: ${details.isEmpty ? 'Not provided' : details}\n\nThis is an uncertain estimate and will not be saved until you review it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Estimate'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _runAi(
        context,
        c,
        workflow: 'unknown food estimate',
        text: '$name; serving/preparation details: $details',
      );
    }
  }

  Future<void> _reviewAi(BuildContext context, TrackerController c) async {
    final question = await _textPrompt(
      context,
      'Nutrition review',
      'Ask about today’s logged meals, goals, or remaining protein',
      multiline: true,
      autofocus: true,
    );
    if (question == null || question.trim().isEmpty || !context.mounted) return;
    final totals = c.dayTotals;
    final validEntries = c.entries.where(usableFoodEntryNutrition).toList();
    final excludedCount = c.entries.length - validEntries.length;
    final foods = validEntries.isEmpty
        ? 'No foods are logged for this day.'
        : validEntries
              .map((entry) {
                final nutrition = entry.total;
                final note = entry.note.trim().isEmpty
                    ? ''
                    : ' (note: ${entry.note.trim()})';
                return '- ${entry.meal}: ${fmt(entry.quantity, digits: 2)} ${entry.unit} ${entry.name}$note; ${fmt(nutrition.kcal)} kcal, P ${fmt(nutrition.protein, digits: 1)} g, C ${fmt(nutrition.carbs, digits: 1)} g, F ${fmt(nutrition.fat, digits: 1)} g';
              })
              .join('\n');
    final payload =
        'User-selected food entries for ${c.selectedDate}:\n$foods\n${excludedCount == 0 ? '' : '\n$excludedCount entry/entries with invalid nutrition were excluded pending review.'}\n\nDeterministic local totals: ${fmt(totals.kcal)} kcal, protein ${fmt(totals.protein, digits: 1)} g, carbohydrates ${fmt(totals.carbs, digits: 1)} g, fat ${fmt(totals.fat, digits: 1)} g. Targets: ${fmt(c.goals.kcal)} kcal and ${fmt(c.goals.protein)} g protein. User question: ${question.trim()}. Give practical informational suggestions using only these entries and totals; do not invent foods or historical data, and do not provide medical advice.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Send this nutrition summary?'),
        content: SingleChildScrollView(
          child: Text(
            'The selected day’s food names, portions, notes, calculated totals, calorie/protein targets, and your question will be sent. Weight history and other profile details are excluded.\n\n$payload',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ask assistant'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _runAi(context, c, workflow: 'nutrition review', text: payload);
    }
  }

  Future<void> _photoAi(
    BuildContext context,
    TrackerController c, {
    bool label = false,
  }) async {
    final picked = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () => chooseImage(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => chooseImage(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final contextText = await _textPrompt(
      context,
      label ? 'Scan nutrition facts' : 'Add optional photo context',
      label
          ? 'Optional: amount you consumed, serving size, and whether you used a partial package.'
          : 'Ingredients, serving size, cooking method, oil/ghee, quantity, or corrections',
      multiline: true,
      allowEmpty: true,
      autofocus: true,
    );
    if (contextText == null || !context.mounted) {
      await _discardPhoto(picked.path);
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Send to Gemini?'),
        content: SingleChildScrollView(
          child: Text(
            'The selected ${label ? 'label photo' : 'food photo'}${contextText.trim().isEmpty ? '' : ' and your context text'} will be sent together to Google for analysis. Nothing else from your profile is included. Continue?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Analyze'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await _runAi(
        context,
        c,
        workflow: label ? 'nutrition label extraction' : 'food photo',
        text: contextText,
        path: picked.path,
        imagePickerPreparationMs: imagePickerPreparationMs,
      );
    } else {
      await _discardPhoto(picked.path);
    }
  }

  Future<void> chooseImage(
    BuildContext sheetContext,
    ImageSource source,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      imagePickerPreparationMs = watch.elapsedMilliseconds;
      if (sheetContext.mounted) Navigator.pop(sheetContext, image);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Image selection failed (${error.runtimeType}).');
      }
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (mounted && context.mounted) {
        _toast(
          context,
          'Could not open the camera or gallery. Check permissions and try again.',
        );
      }
    }
  }

  Future<void> _runAi(
    BuildContext context,
    TrackerController c, {
    required String workflow,
    required String text,
    String? path,
    int imagePickerPreparationMs = 0,
  }) async {
    try {
      while (context.mounted) {
        if (!context.mounted) return;
        if (!widget.aiConfigured || !c.goals.aiEnabled) {
          setState(() => failedAiDraft = text.trim().isEmpty ? workflow : text);
          final message = !widget.aiConfigured
              ? 'AI is unavailable until a Gemini API key is configured and AI is enabled. Your request is shown below for manual logging.'
              : 'AI is turned off in Settings. Your request is shown below for manual logging.';
          _toast(context, message);
          return;
        }
        final client = widget.aiClient ?? AiAssistant.instance;
        final navigator = Navigator.of(context, rootNavigator: true);
        Future<void>? loadingClosed;
        final uiWatch = Stopwatch()..start();
        String? requestId;
        var loadingReadyLogged = false;
        var resultReadyLogged = false;
        try {
          loadingClosed = showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final id = requestId;
                if (id != null && !loadingReadyLogged) {
                  loadingReadyLogged = true;
                  AiAssistant.logUiStage(
                    requestId: id,
                    workflow: workflow,
                    event: 'loading_screen_ready',
                    elapsedMs: uiWatch.elapsedMilliseconds,
                  );
                }
              });
              return const _AiLoadingDialog();
            },
          );
          if (!context.mounted) return;
          final proposal = (path == null
              ? client.analyze(
                  text: text,
                  workflow: workflow,
                  onRequestId: (id) {
                    requestId = id;
                    AiAssistant.logUiStage(
                      requestId: id,
                      workflow: workflow,
                      event: 'ui_request_started',
                      elapsedMs: uiWatch.elapsedMilliseconds,
                    );
                  },
                )
              : client.analyzePhoto(
                  context: text,
                  path: path,
                  workflow: workflow,
                  pickerPreparationMs: imagePickerPreparationMs,
                  onRequestId: (id) {
                    requestId = id;
                    AiAssistant.logUiStage(
                      requestId: id,
                      workflow: workflow,
                      event: 'ui_request_started',
                      elapsedMs: uiWatch.elapsedMilliseconds,
                    );
                  },
                ));
          final result = await proposal;
          if (navigator.mounted && navigator.canPop()) navigator.pop();
          await loadingClosed;
          if (!context.mounted) return;
          setState(() => failedAiDraft = null);
          if (result.clarificationRequired) {
            await showDialog<void>(
              context: context,
              builder: (dialogContext) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final id = requestId;
                  if (id != null && !resultReadyLogged) {
                    resultReadyLogged = true;
                    AiAssistant.logUiStage(
                      requestId: id,
                      workflow: workflow,
                      event: 'clarification_screen_ready',
                      elapsedMs: uiWatch.elapsedMilliseconds,
                    );
                  }
                });
                return AlertDialog(
                  title: const Text('More detail needed'),
                  content: Text(
                    '${result.summary}\n\nNothing was saved. Revise the description to say how much you ate, then analyze again.',
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Revise description'),
                    ),
                  ],
                );
              },
            );
            return;
          }
          await showDialog<void>(
            context: context,
            builder: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final id = requestId;
                if (id != null && !resultReadyLogged) {
                  resultReadyLogged = true;
                  AiAssistant.logUiStage(
                    requestId: id,
                    workflow: workflow,
                    event: 'review_screen_ready',
                    elapsedMs: uiWatch.elapsedMilliseconds,
                  );
                }
              });
              return workflow == 'nutrition review'
                  ? _AiAdviceDialog(proposal: result)
                  : _AiReviewDialog(proposal: result, initialNote: text);
            },
          );
          return;
        } catch (error) {
          final id = requestId;
          if (id != null) {
            AiAssistant.logUiStage(
              requestId: id,
              workflow: workflow,
              event: 'ui_failure',
              elapsedMs: uiWatch.elapsedMilliseconds,
              fields: {'error_category': AiAssistant.failureInfo(error).code},
            );
          }
          if (loadingClosed != null) {
            if (navigator.mounted && navigator.canPop()) navigator.pop();
            await loadingClosed;
          }
          if (!context.mounted) return;
          final failure = AiAssistant.failureInfo(error);
          setState(() => failedAiDraft = text.trim().isEmpty ? workflow : text);
          final action = await showDialog<_AiFailureAction>(
            context: context,
            builder: (_) => _AiFailureDialog(
              failure: failure,
              retainedInput: text,
              photoWasUsed: path != null,
            ),
          );
          if (action == _AiFailureAction.retry && failure.retryAllowed) {
            continue;
          }
          if (action == _AiFailureAction.manual && context.mounted) {
            _toast(
              context,
              'Nothing was saved. Use food search or Custom food to log it manually.',
            );
          }
          return;
        }
      }
    } finally {
      if (path != null) await _discardPhoto(path);
    }
  }
}

Future<void> _discardPhoto(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Temporary photo cleanup is best effort; the picker cache is still app-private.
  }
}

class _SavedMealEdit {
  const _SavedMealEdit(this.name, this.items);
  final String name;
  final List<FoodEntry> items;
}

class _SavedMealCard extends StatelessWidget {
  const _SavedMealCard({
    required this.meal,
    required this.busy,
    required this.onFavourite,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
  });
  final Map<String, Object?> meal;
  final bool busy;
  final VoidCallback onFavourite, onEdit, onDelete, onAdd;

  @override
  Widget build(BuildContext context) {
    final rows = (jsonDecode(meal['data'] as String) as List)
        .map((row) => FoodEntry.fromMap(Map<String, Object?>.from(row as Map)))
        .where(usableFoodEntryNutrition);
    final items = rows.toList();
    final total = items.fold(
      const Nutrition(),
      (sum, item) => sum + item.total,
    );
    final favorite = (meal['favourite'] as num? ?? 0) == 1;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meal['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: favorite ? 'Unfavourite meal' : 'Favourite meal',
                onPressed: onFavourite,
                icon: Icon(
                  favorite ? Icons.favorite : Icons.favorite_border,
                  color: favorite ? Theme.of(context).colorScheme.error : null,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit saved meal')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          Text(
            items.map((item) => item.name).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${fmt(total.kcal)} kcal · P ${fmt(total.protein, digits: 1)} g · C ${fmt(total.carbs, digits: 1)} g · F ${fmt(total.fat, digits: 1)} g',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onAdd,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add portion to diary'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedMealEditDialog extends StatefulWidget {
  const _SavedMealEditDialog({required this.name, required this.items});
  final String name;
  final List<FoodEntry> items;
  @override
  State<_SavedMealEditDialog> createState() => _SavedMealEditDialogState();
}

class _SavedMealEditDialogState extends State<_SavedMealEditDialog> {
  late final TextEditingController name;
  late final List<_SavedMealItemFields> items;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.name);
    items = widget.items.map(_SavedMealItemFields.new).toList();
  }

  @override
  void dispose() {
    name.dispose();
    for (final item in items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit saved meal'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Meal name'),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < items.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: items[i].foodName,
                              decoration: const InputDecoration(
                                labelText: 'Food',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove food',
                            onPressed: () => setState(() {
                              items.removeAt(i).dispose();
                            }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      TextField(
                        controller: items[i].quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Quantity (${items[i].original.unit})',
                        ),
                      ),
                      Row(
                        children: [
                          for (var j = 0; j < 4; j++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: TextField(
                                  controller: items[i].nutrition[j],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: ['kcal', 'P g', 'C g', 'F g'][j],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (items.isEmpty)
              const Text(
                'This saved meal has no foods. Add entries before saving a new template.',
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (name.text.trim().isEmpty || items.isEmpty) return;
          final updated = <FoodEntry>[];
          for (final item in items) {
            final quantity = double.tryParse(item.quantity.text.trim());
            final values = item.nutrition
                .map((field) => double.tryParse(field.text.trim()))
                .toList();
            if (item.foodName.text.trim().isEmpty ||
                quantity == null ||
                !quantity.isFinite ||
                quantity <= 0 ||
                values.any(
                  (value) => value == null || !value.isFinite || value < 0,
                )) {
              _toast(
                context,
                'Check each food, quantity, and nutrition value.',
              );
              return;
            }
            final nutrition = Nutrition(
              kcal: values[0]!,
              protein: values[1]!,
              carbs: values[2]!,
              fat: values[3]!,
            );
            if (!plausibleNutrition(nutrition, unit: 'serving')) {
              _toast(context, 'Nutrition values look inconsistent.');
              return;
            }
            updated.add(
              FoodEntry(
                id: item.original.id,
                foodId: item.original.foodId,
                name: item.foodName.text.trim(),
                date: item.original.date,
                meal: item.original.meal,
                quantity: quantity,
                unit: item.original.unit,
                baseNutrition: nutrition,
                nutritionBasis: 'portion',
                originalQuantity: quantity,
                originalUnit: item.original.unit,
                note: item.original.note,
                source: item.original.source,
              ),
            );
          }
          Navigator.pop(context, _SavedMealEdit(name.text.trim(), updated));
        },
        child: const Text('Save template'),
      ),
    ],
  );
}

class _SavedMealItemFields {
  _SavedMealItemFields(this.original)
    : foodName = TextEditingController(text: original.name),
      quantity = TextEditingController(text: original.quantity.toString()),
      nutrition = [
        TextEditingController(text: original.total.kcal.toString()),
        TextEditingController(text: original.total.protein.toString()),
        TextEditingController(text: original.total.carbs.toString()),
        TextEditingController(text: original.total.fat.toString()),
      ];
  final FoodEntry original;
  final TextEditingController foodName, quantity;
  final List<TextEditingController> nutrition;
  void dispose() {
    foodName.dispose();
    quantity.dispose();
    for (final field in nutrition) {
      field.dispose();
    }
  }
}

class _LogResult {
  const _LogResult(this.quantity, this.meal, this.note, {this.nutrition});
  final double quantity;
  final String meal, note;
  final Nutrition? nutrition;
}

class _LogFoodDialog extends StatefulWidget {
  const _LogFoodDialog({
    required this.food,
    this.initialQuantity,
    this.initialMeal = 'Breakfast',
    this.initialNote = '',
    this.initialNutrition,
    this.allowNutritionEdit = false,
  });
  final Food food;
  final double? initialQuantity;
  final String initialMeal, initialNote;
  final Nutrition? initialNutrition;
  final bool allowNutritionEdit;
  @override
  State<_LogFoodDialog> createState() => _LogFoodDialogState();
}

class _LogFoodDialogState extends State<_LogFoodDialog> {
  late final TextEditingController quantity;
  late final TextEditingController note;
  late final List<TextEditingController> nutrition;
  late String meal;
  @override
  void initState() {
    super.initState();
    quantity = TextEditingController(
      text: (widget.initialQuantity ?? widget.food.serving).toString(),
    );
    note = TextEditingController(text: widget.initialNote);
    final initialNutrition = widget.initialNutrition ?? widget.food.nutrition;
    nutrition = [
      TextEditingController(text: initialNutrition.kcal.toString()),
      TextEditingController(text: initialNutrition.protein.toString()),
      TextEditingController(text: initialNutrition.carbs.toString()),
      TextEditingController(text: initialNutrition.fat.toString()),
    ];
    meal = widget.initialMeal;
  }

  @override
  void dispose() {
    quantity.dispose();
    note.dispose();
    for (final field in nutrition) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.food.name),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Quantity (${widget.food.unit})',
            ),
          ),
          if (widget.allowNutritionEdit) ...[
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Nutrition for this quantity'),
            ),
            for (var i = 0; i < nutrition.length; i++)
              TextField(
                controller: nutrition[i],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: [
                    'Calories (kcal)',
                    'Protein (g)',
                    'Carbs (g)',
                    'Fat (g)',
                  ][i],
                ),
              ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: meal,
            decoration: const InputDecoration(labelText: 'Meal'),
            items: [
              'Breakfast',
              'Lunch',
              'Dinner',
              'Snack',
            ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => setState(() => meal = v ?? meal),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            decoration: const InputDecoration(
              labelText: 'Optional note (oil, preparation)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final q = double.tryParse(quantity.text);
          if (q == null ||
              q <= 0 ||
              q > (widget.food.isMassBased ? 5000 : 100)) {
            _toast(context, 'Enter a realistic quantity for this serving.');
            return;
          }
          Nutrition? editedNutrition;
          if (widget.allowNutritionEdit) {
            final values = nutrition
                .map((field) => double.tryParse(field.text))
                .toList();
            if (values.any(
              (value) => value == null || !value.isFinite || value < 0,
            )) {
              _toast(context, 'Enter valid non-negative nutrition values.');
              return;
            }
            editedNutrition = Nutrition(
              kcal: values[0]!,
              protein: values[1]!,
              carbs: values[2]!,
              fat: values[3]!,
            );
            if (!plausibleNutrition(editedNutrition, unit: 'serving')) {
              _toast(
                context,
                'Nutrition values look inconsistent. Please correct them.',
              );
              return;
            }
          }
          Navigator.pop(
            context,
            _LogResult(q, meal, note.text, nutrition: editedNutrition),
          );
        },
        child: Text(
          widget.allowNutritionEdit ? 'Save changes' : 'Add to diary',
        ),
      ),
    ],
  );
}

class _ManualFoodInput {
  const _ManualFoodInput(this.food, this.quantity);
  final Food food;
  final double quantity;
}

class _FoodEditDialog extends StatefulWidget {
  const _FoodEditDialog();
  @override
  State<_FoodEditDialog> createState() => _FoodEditDialogState();
}

class _FoodEditDialogState extends State<_FoodEditDialog> {
  final name = TextEditingController();
  final quantity = TextEditingController(text: '100');
  final unit = TextEditingController(text: 'g');
  final fields = List.generate(4, (_) => TextEditingController());
  String basis = 'portion';

  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add food manually'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Food name'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: basis,
            decoration: const InputDecoration(labelText: 'Nutrition basis'),
            items: const [
              DropdownMenuItem(
                value: 'portion',
                child: Text('Nutrition for the amount I ate'),
              ),
              DropdownMenuItem(
                value: 'per100',
                child: Text('Nutrition per 100 g / 100 ml'),
              ),
            ],
            onChanged: (value) => setState(() => basis = value ?? 'portion'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: basis == 'portion'
                  ? 'Amount eaten'
                  : 'Amount consumed',
              hintText: basis == 'per100' ? 'e.g. 200' : 'e.g. 200',
            ),
          ),
          TextField(
            controller: unit,
            decoration: InputDecoration(
              labelText: 'Unit',
              helperText: basis == 'per100'
                  ? 'Use g or ml for this basis.'
                  : 'Examples: g, ml, piece, cup.',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            basis == 'portion'
                ? 'Enter total nutrition for the amount above. Example: 200 g cooked rice — 260 kcal, 5 g protein, 56 g carbs, 0.6 g fat.'
                : 'Enter nutrition per 100 g or per 100 ml. NutriTrack scales it to the consumed amount.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < fields.length; i++)
            TextField(
              controller: fields[i],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: [
                  'Calories (kcal)',
                  'Protein (g)',
                  'Carbohydrates (g)',
                  'Fat (g)',
                ][i],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'This food is saved in your local food library so you can reuse it. You’ll confirm the meal and amount before it is added to your diary.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final amount = double.tryParse(quantity.text.trim());
          final normalizedUnit = unit.text.trim().toLowerCase();
          final values = fields
              .map((field) => double.tryParse(field.text.trim()))
              .toList();
          final hasCompatibleUnit =
              basis == 'portion' ||
              const {
                'g',
                'gm',
                'gram',
                'grams',
                'ml',
                'milliliter',
                'millilitre',
              }.contains(normalizedUnit);
          if (name.text.trim().isEmpty ||
              normalizedUnit.isEmpty ||
              amount == null ||
              !amount.isFinite ||
              amount <= 0 ||
              !hasCompatibleUnit ||
              values.any((n) => n == null || !n.isFinite || n < 0)) {
            _toast(
              context,
              'Enter a food name, positive amount, compatible unit, and valid nutrition values.',
            );
            return;
          }
          final enteredNutrition = Nutrition(
            kcal: values[0]!,
            protein: values[1]!,
            carbs: values[2]!,
            fat: values[3]!,
          );
          final serving = basis == 'per100' ? 100.0 : amount;
          final food = Food(
            name: name.text.trim(),
            serving: serving,
            unit: normalizedUnit,
            source: 'Custom',
            nutrition: enteredNutrition,
            nutritionBasis: basis,
            referenceQuantity: serving,
          );
          final nutrition = food.perHundredNutrition;
          if (!plausibleNutrition(
            nutrition,
            unit: food.isMassBased ? food.unit : 'serving',
          )) {
            _toast(
              context,
              'Nutrition values look inconsistent. Check kcal and macro units.',
            );
            return;
          }
          Navigator.pop(context, _ManualFoodInput(food, amount));
        },
        child: const Text('Save and log food'),
      ),
    ],
  );
}

class _RecipeInput {
  const _RecipeInput(this.name, this.servings, this.ingredients);
  final String name;
  final double servings;
  final List<Map<String, Object?>> ingredients;
}

class _RecipeDialog extends StatefulWidget {
  const _RecipeDialog({required this.foods});
  final List<Food> foods;
  @override
  State<_RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends State<_RecipeDialog> {
  final name = TextEditingController();
  final servings = TextEditingController(text: '2');
  final portions = <String, double>{};
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New recipe'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Recipe name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: servings,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of servings',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'For each ingredient, enter a multiple of the serving shown below. NutriTrack totals the ingredients and divides by recipe servings.',
            ),
            const SizedBox(height: 8),
            ...widget.foods.map(
              (f) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(f.name),
                subtitle: Text(
                  '${fmt(f.nutrition.kcal)} kcal per ${fmt(f.serving, digits: 1)} ${f.unit}',
                ),
                value: portions.containsKey(f.id),
                onChanged: (v) => setState(
                  () => v == true ? portions[f.id] = 1 : portions.remove(f.id),
                ),
                secondary: portions.containsKey(f.id)
                    ? SizedBox(
                        width: 80,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '× servings',
                            hintText: '1',
                          ),
                          onChanged: (v) =>
                              portions[f.id] = double.tryParse(v) ?? 1,
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final count = double.tryParse(servings.text) ?? 0;
          if (name.text.trim().isEmpty || count <= 0 || portions.isEmpty) {
            return;
          }
          final rows = <Map<String, Object?>>[];
          for (final f in widget.foods.where(
            (f) => portions.containsKey(f.id),
          )) {
            final servingMultiplier = portions[f.id]!;
            rows.add({
              ...f.nutrition.toMap(),
              'quantity': servingMultiplier,
              'food_id': f.id,
              'food_name': f.name,
              'food_serving': f.serving,
              'food_unit': f.unit,
              'ingredient_amount': f.serving * servingMultiplier,
            });
          }
          Navigator.pop(context, _RecipeInput(name.text.trim(), count, rows));
        },
        child: const Text('Save recipe'),
      ),
    ],
  );
}

class _RepeatScheduleEditor extends StatefulWidget {
  const _RepeatScheduleEditor({
    required this.startDate,
    required this.initial,
    required this.onChanged,
  });
  final String startDate;
  final RepeatRule initial;
  final ValueChanged<RepeatRule> onChanged;
  @override
  State<_RepeatScheduleEditor> createState() => _RepeatScheduleEditorState();
}

class _RepeatScheduleEditorState extends State<_RepeatScheduleEditor> {
  late RepeatFrequency frequency;
  late Set<int> weekdays;
  String? until;
  static const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  @override
  void initState() {
    super.initState();
    frequency = widget.initial.frequency;
    weekdays = widget.initial.weekdays.toSet();
    if (frequency == RepeatFrequency.weekly && weekdays.isEmpty) {
      weekdays.add(
        DateTime.tryParse(widget.startDate)?.weekday ?? DateTime.now().weekday,
      );
    }
    until = widget.initial.until;
  }

  void publish() => widget.onChanged(
    RepeatRule(
      frequency: frequency,
      weekdays: weekdays.toList()..sort(),
      until: until,
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<RepeatFrequency>(
        initialValue: frequency,
        decoration: const InputDecoration(labelText: 'Repeat'),
        items: const [
          DropdownMenuItem(
            value: RepeatFrequency.none,
            child: Text('Does not repeat'),
          ),
          DropdownMenuItem(
            value: RepeatFrequency.daily,
            child: Text('Every day'),
          ),
          DropdownMenuItem(
            value: RepeatFrequency.weekly,
            child: Text('Every week on selected weekday'),
          ),
          DropdownMenuItem(
            value: RepeatFrequency.custom,
            child: Text('Custom weekdays'),
          ),
        ],
        onChanged: (value) => setState(() {
          frequency = value ?? RepeatFrequency.none;
          if (frequency == RepeatFrequency.weekly && weekdays.length != 1) {
            weekdays = {
              weekdays.isEmpty
                  ? DateTime.tryParse(widget.startDate)?.weekday ??
                        DateTime.now().weekday
                  : weekdays.first,
            };
          }
          publish();
        }),
      ),
      if (frequency == RepeatFrequency.weekly)
        Wrap(
          spacing: 4,
          children: [
            for (var day = 1; day <= 7; day++)
              ChoiceChip(
                label: Text(labels[day - 1]),
                selected: weekdays.contains(day),
                onSelected: (_) => setState(() {
                  weekdays = {day};
                  publish();
                }),
              ),
          ],
        ),
      if (frequency == RepeatFrequency.weekly)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Repeats every ${labels[(weekdays.isEmpty ? DateTime.now().weekday : weekdays.first) - 1]}.',
          ),
        ),
      if (frequency == RepeatFrequency.custom)
        Wrap(
          spacing: 4,
          children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                label: Text(labels[day - 1]),
                selected: weekdays.contains(day),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    weekdays.add(day);
                  } else {
                    weekdays.remove(day);
                  }
                  publish();
                }),
              ),
          ],
        ),
      TextButton.icon(
        onPressed: () async {
          final now = DateTime.now();
          final selected = await showDatePicker(
            context: context,
            initialDate: DateTime.tryParse(until ?? widget.startDate) ?? now,
            firstDate: DateTime.tryParse(widget.startDate) ?? now,
            lastDate: DateTime(2100),
          );
          if (selected != null) {
            setState(() {
              until = dayKey(selected);
              publish();
            });
          }
        },
        icon: const Icon(Icons.event_busy_outlined),
        label: Text(
          until == null ? 'Add end date (optional)' : 'Ends $until · Change',
        ),
      ),
      if (until != null)
        TextButton(
          onPressed: () => setState(() {
            until = null;
            publish();
          }),
          child: const Text('Remove end date'),
        ),
    ],
  );
}

class _AiLoadingDialog extends StatefulWidget {
  const _AiLoadingDialog();

  @override
  State<_AiLoadingDialog> createState() => _AiLoadingDialogState();
}

class _AiLoadingDialogState extends State<_AiLoadingDialog> {
  late final Stopwatch watch;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    watch = Stopwatch()..start();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = watch.elapsed >= const Duration(seconds: 20);
    return AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              waiting
                  ? 'Still working… this can take up to a minute. Keep this screen open.'
                  : 'Connecting to Gemini…',
            ),
          ),
        ],
      ),
    );
  }
}

enum _AiFailureAction { retry, manual, dismiss }

class _AiFailureDialog extends StatelessWidget {
  const _AiFailureDialog({
    required this.failure,
    required this.retainedInput,
    required this.photoWasUsed,
  });

  final AiFailureInfo failure;
  final String retainedInput;
  final bool photoWasUsed;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(failure.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(failure.message),
          if (retainedInput.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Your text is retained here for manual logging:'),
            SelectableText(retainedInput),
          ],
          if (photoWasUsed)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'The selected photo is discarded after this attempt.',
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, _AiFailureAction.dismiss),
        child: const Text('Close'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _AiFailureAction.manual),
        child: const Text('Continue manually'),
      ),
      if (failure.retryAllowed)
        FilledButton(
          onPressed: () => Navigator.pop(context, _AiFailureAction.retry),
          child: const Text('Try again'),
        ),
    ],
  );
}

class _AiReviewDialog extends StatefulWidget {
  const _AiReviewDialog({required this.proposal, required this.initialNote});
  final AiProposal proposal;
  final String initialNote;
  @override
  State<_AiReviewDialog> createState() => _AiReviewDialogState();
}

class _AiReviewDialogState extends State<_AiReviewDialog> {
  late final List<List<TextEditingController>> values;
  String meal = 'Snack';

  Nutrition? _preview(int index) {
    final row = values[index];
    final quantity = double.tryParse(row[1].text);
    final nutritionValues = row
        .skip(2)
        .map((field) => double.tryParse(field.text))
        .toList();
    if (quantity == null || nutritionValues.any((value) => value == null)) {
      return null;
    }
    try {
      final ratio = quantityRatio(
        quantity,
        widget.proposal.items[index].unit,
        widget.proposal.items[index].consumedQuantity,
        widget.proposal.items[index].unit,
      );
      return Nutrition(
        kcal: nutritionValues[0]! * ratio,
        protein: nutritionValues[1]! * ratio,
        carbs: nutritionValues[2]! * ratio,
        fat: nutritionValues[3]! * ratio,
      );
    } on ArgumentError {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    values = widget.proposal.items
        .map(
          (f) => [
            TextEditingController(text: f.name),
            TextEditingController(text: f.consumedQuantity.toString()),
            TextEditingController(text: f.totalNutrition.kcal.toString()),
            TextEditingController(text: f.totalNutrition.protein.toString()),
            TextEditingController(text: f.totalNutrition.carbs.toString()),
            TextEditingController(text: f.totalNutrition.fat.toString()),
          ],
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review estimate'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.proposal.summary),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: meal,
              decoration: const InputDecoration(labelText: 'Meal'),
              items: [
                'Breakfast',
                'Lunch',
                'Dinner',
                'Snack',
              ].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
              onChanged: (v) => setState(() => meal = v ?? meal),
            ),
            ...List.generate(
              values.length,
              (i) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant
                        .withValues(alpha: .4),
                  ),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${widget.proposal.items[i].confidence.toUpperCase()} confidence · ${widget.proposal.items[i].assumptions}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: values[i][0],
                      decoration: const InputDecoration(labelText: 'Food'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: values[i][1],
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'Current amount (${widget.proposal.items[i].unit})',
                      ),
                    ),
                    if (widget.proposal.items[i].labelReference
                        case final reference?)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Label reference: ${fmt(reference.quantity, digits: 2)} ${reference.unit} · ${fmt(reference.nutrition.kcal)} kcal, P ${fmt(reference.nutrition.protein, digits: 1)} g, C ${fmt(reference.nutrition.carbs, digits: 1)} g, F ${fmt(reference.nutrition.fat, digits: 1)} g (${reference.basis.replaceAll('_', ' ')})',
                        ),
                      ),
                    for (final pair in const [(0, 1), (2, 3)])
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            for (final j in [pair.$1, pair.$2])
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: j == pair.$1 ? 8 : 0,
                                  ),
                                  child: TextField(
                                    controller: values[i][j + 2],
                                    onChanged: (_) => setState(() {}),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: [
                                        'Original kcal total',
                                        'Original protein g',
                                        'Original carbs g',
                                        'Original fat g',
                                      ][j],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (_preview(i) case final preview?)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Current portion: ${fmt(preview.kcal)} kcal · P ${fmt(preview.protein, digits: 1)} g · C ${fmt(preview.carbs, digits: 1)} g · F ${fmt(preview.fat, digits: 1)} g',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.proposal.clarificationRequired
                  ? 'Clarification required: ${widget.proposal.summary}. Nothing can be saved until the amount eaten is clear.'
                  : 'Edit the current amount or original estimate. Portion totals are calculated once from the original estimate.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Discard'),
      ),
      FilledButton(
        onPressed: () async {
          final c = TrackerScope.of(context);
          if (widget.proposal.clarificationRequired) return;
          final reviewed = <(AiFoodProposal, double, Nutrition)>[];
          for (var i = 0; i < values.length; i++) {
            final row = values[i];
            final vals = row.map((x) => x.text.trim()).toList();
            final q = double.tryParse(vals[1]),
                k = double.tryParse(vals[2]),
                p = double.tryParse(vals[3]),
                carbs = double.tryParse(vals[4]),
                fat = double.tryParse(vals[5]);
            final proposal = widget.proposal.items[i];
            final unit = proposal.unit;
            final candidate =
                k == null || p == null || carbs == null || fat == null
                ? null
                : Nutrition(kcal: k, protein: p, carbs: carbs, fat: fat);
            if (vals[0].isEmpty ||
                q == null ||
                q <= 0 ||
                q >
                    (const {'g', 'ml'}.contains(unit.toLowerCase())
                        ? 2000
                        : 100) ||
                candidate == null ||
                !plausibleNutrition(candidate, unit: 'serving')) {
              if (context.mounted) {
                _toast(context, 'Correct all proposal fields before saving.');
              }
              return;
            }
            try {
              quantityRatio(q, unit, proposal.consumedQuantity, proposal.unit);
            } on ArgumentError {
              _toast(context, 'Current amount must use a compatible unit.');
              return;
            }
            reviewed.add((proposal, q, candidate));
          }
          await AiProposalCommitter.commit(
            confirmed: true,
            foods: reviewed.map((x) => x.$1).toList(),
            persist: (proposal) async {
              final row = reviewed.firstWhere((x) => identical(x.$1, proposal));
              await c.addEntry(
                FoodEntry(
                  name: proposal.name,
                  date: c.selectedDate,
                  meal: meal,
                  quantity: row.$2,
                  unit: proposal.unit,
                  baseNutrition: row.$3,
                  nutritionBasis: 'portion',
                  originalQuantity: proposal.consumedQuantity,
                  originalUnit: proposal.unit,
                  referenceQuantity: proposal.labelReference?.quantity,
                  referenceUnit: proposal.labelReference?.unit,
                  referenceNutrition: proposal.labelReference?.nutrition,
                  note: [
                    widget.initialNote.trim(),
                    proposal.assumptions,
                  ].where((value) => value.isNotEmpty).join(' · '),
                  source: proposal.labelReference == null
                      ? 'AI estimate · ${proposal.confidence} confidence'
                      : 'Nutrition label extraction · ${proposal.confidence} confidence',
                ),
              );
            },
          );
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Confirm and save'),
      ),
    ],
  );
}

class _AiAdviceDialog extends StatelessWidget {
  const _AiAdviceDialog({required this.proposal});
  final AiProposal proposal;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nutrition review'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(proposal.summary),
            if (proposal.items.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 14, bottom: 6),
                child: Text(
                  'Optional food ideas · not logged',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            for (final food in proposal.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(food.name),
                subtitle: Text(
                  '${fmt(food.totalNutrition.kcal)} kcal · P ${fmt(food.totalNutrition.protein, digits: 1)} g · C ${fmt(food.totalNutrition.carbs, digits: 1)} g · F ${fmt(food.totalNutrition.fat, digits: 1)} g',
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Informational only. Your diary and totals are unchanged.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = TrackerScope.of(context);
    final weights = c.weights.reversed.toList();
    final average = c.sevenDayAverage;
    return PageFrame(
      title: 'Progress',
      subtitle: 'Trends over time',
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Weight trend'),
              if (weights.length < 2)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weights.isEmpty
                          ? 'Log a few measurements to see your trend and 7-day average.'
                          : 'Add one more measurement to see your trend.',
                    ),
                    if (weights.isEmpty) ...[
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () => showWeightDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Log weight'),
                      ),
                    ],
                  ],
                )
              else
                SizedBox(
                  height: 190,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          isCurved: true,
                          color: Theme.of(context).colorScheme.primary,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                          spots: [
                            for (var i = 0; i < weights.length; i++)
                              FlSpot(i.toDouble(), weights[i].kg),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      context,
                      'Latest',
                      c.latestWeight == null
                          ? '—'
                          : '${fmt(c.latestWeight!.kg, digits: 1)} kg',
                    ),
                  ),
                  Expanded(
                    child: _stat(
                      context,
                      '7-day avg',
                      average == null ? '—' : '${fmt(average, digits: 1)} kg',
                    ),
                  ),
                  Expanded(
                    child: _stat(
                      context,
                      'Target',
                      '${fmt(c.goals.targetMinKg)}–${fmt(c.goals.targetMaxKg)} kg',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Weight history'),
              if (c.weights.isEmpty)
                Text(
                  'Measurements stay on this device. Add a weight entry to start your history.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                ...c.weights.map(
                  (w) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${fmt(w.kg, digits: 1)} kg'),
                    subtitle: Text(
                      '${todayLabel(w.date)}${w.note.isEmpty ? '' : ' · ${w.note}'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') showWeightDialog(context, existing: w);
                        if (v == 'delete') c.deleteWeight(w.id);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Nutrition highlights'),
              Text(
                'Today: ${fmt(c.dayTotals.kcal)} kcal · ${fmt(c.dayTotals.protein)} g protein',
              ),
              Text(
                'Daily targets: ${fmt(c.goals.kcal)} kcal · ${fmt(c.goals.protein)} g protein',
              ),
              const SizedBox(height: 8),
              Text(
                'Weight readings vary with hydration and normal daily fluctuation. Look at longer trends.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Calorie and protein history'),
              for (var offset = 6; offset >= 0; offset--)
                _nutritionDayRow(
                  context,
                  c,
                  DateTime.now().subtract(Duration(days: offset)),
                ),
            ],
          ),
        ),
        const SectionTitle('Your data'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _export(context, c, csv: true),
              icon: const Icon(Icons.table_view),
              label: const Text('Export CSV'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _export(context, c),
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Create backup'),
            ),
            OutlinedButton.icon(
              onPressed: () => _restore(context, c),
              icon: const Icon(Icons.restore),
              label: const Text('Restore backup'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );

  Widget _nutritionDayRow(
    BuildContext context,
    TrackerController c,
    DateTime date,
  ) {
    final key = dayKey(date);
    final rows = c.historyEntries.where((e) => e.date == key).toList();
    final total = rows.fold(const Nutrition(), (sum, e) => sum + e.total);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(todayLabel(key))),
          Expanded(
            flex: 3,
            child: Text(
              rows.isEmpty ? 'No food logged' : '${fmt(total.kcal)} kcal',
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              rows.isEmpty ? '—' : '${fmt(total.protein, digits: 1)} g protein',
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _export(
  BuildContext context,
  TrackerController c, {
  bool csv = false,
}) async {
  try {
    String contents;
    String filename;
    if (csv) {
      final b = StringBuffer(
        'type,date,name,quantity,unit,kcal,protein_g,carbs_g,fat_g,note\n',
      );
      final allEntries = (await c.db.all('entries')).map(FoodEntry.fromMap);
      for (final e in allEntries) {
        b.writeln(
          'food,${e.date},"${e.name.replaceAll('"', '""')}",${e.quantity},${e.unit},${e.total.kcal},${e.total.protein},${e.total.carbs},${e.total.fat},"${e.note.replaceAll('"', '""')}"',
        );
      }
      for (final w in c.weights) {
        b.writeln(
          'weight,${w.date},weight,${w.kg},kg,,,,,"${w.note.replaceAll('"', '""')}"',
        );
      }
      for (final r in c.runLogs) {
        b.writeln(
          'run,${r['date']},run,${r['distance_km']},km,,,,,"${r['note']}"',
        );
      }
      contents = b.toString();
      filename = 'nourish-export.csv';
    } else {
      contents = await c.db.exportJson();
      filename = 'nourish-backup.json';
    }
    final uri = await FilePicker.saveFile(
      fileName: filename,
      bytes: Uint8List.fromList(utf8.encode(contents)),
      mimeType: csv ? 'text/csv' : 'application/json',
      dialogTitle: csv ? 'Export CSV' : 'Save local backup',
    );
    if (uri != null && context.mounted) _toast(context, 'Export saved.');
  } catch (e) {
    if (context.mounted) _toast(context, 'Export failed: $e');
  }
}

Future<void> _restore(BuildContext context, TrackerController c) async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result.isEmpty || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'Restoring replaces your current local diary, food library, weight and activity data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace local data'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await c.db.restoreJson(
        utf8.decode(await result.first.xFile.readAsBytes()),
      );
      await c.load();
      if (context.mounted) _toast(context, 'Backup restored.');
    }
  } catch (e) {
    if (context.mounted) _toast(context, 'Restore failed: $e');
  }
}
