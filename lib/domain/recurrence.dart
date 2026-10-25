import 'dart:convert';

enum RepeatFrequency { none, daily, weekly, custom }

class RepeatRule {
  const RepeatRule({
    this.frequency = RepeatFrequency.none,
    this.weekdays = const [],
    this.until,
  });

  final RepeatFrequency frequency;

  /// DateTime weekday numbers: Monday=1 through Sunday=7.
  final List<int> weekdays;
  final String? until;

  Map<String, Object?> toMap() => {
    'frequency': frequency.name,
    'weekdays': weekdays,
    'until': until,
  };

  factory RepeatRule.fromMap(Map? map) {
    if (map == null) return const RepeatRule();
    final frequency = RepeatFrequency.values.firstWhere(
      (v) => v.name == map['frequency'],
      orElse: () => RepeatFrequency.none,
    );
    final weekdays =
        (map['weekdays'] as List? ?? [])
            .whereType<num>()
            .map((v) => v.toInt())
            .where((v) => v >= 1 && v <= 7)
            .toSet()
            .toList()
          ..sort();
    return RepeatRule(
      frequency: frequency,
      weekdays: weekdays,
      until: map['until'] as String?,
    );
  }
}

List<DateTime> repeatOccurrences({
  required DateTime start,
  required RepeatRule rule,
  required DateTime from,
  required DateTime through,
  Iterable<String> excludedDates = const [],
}) {
  final startDay = DateTime(start.year, start.month, start.day);
  final fromDay = DateTime(from.year, from.month, from.day);
  final throughDay = DateTime(through.year, through.month, through.day);
  final until = rule.until == null ? null : DateTime.tryParse(rule.until!);
  final excluded = excludedDates.toSet();
  if (throughDay.isBefore(startDay) || fromDay.isAfter(throughDay)) return [];
  final first = fromDay.isAfter(startDay) ? fromDay : startDay;
  final result = <DateTime>[];
  for (
    var day = first;
    !day.isAfter(throughDay);
    day = day.add(const Duration(days: 1))
  ) {
    if (until != null && day.isAfter(until)) break;
    final selected = switch (rule.frequency) {
      RepeatFrequency.none => day == startDay,
      RepeatFrequency.daily => true,
      RepeatFrequency.weekly =>
        day.weekday ==
            (rule.weekdays.isEmpty ? startDay.weekday : rule.weekdays.first),
      RepeatFrequency.custom => rule.weekdays.contains(day.weekday),
    };
    if (selected &&
        !excluded.contains(day.toIso8601String().substring(0, 10))) {
      result.add(day);
    }
  }
  return result;
}

/// Expands a persisted series into display-only occurrence rows; no occurrence
/// is inserted into the plans table. The occurrence ID is stable and unique.
List<Map<String, Object?>> expandPlanSeries(
  Map<String, Object?> plan, {
  required DateTime from,
  required DateTime through,
}) {
  final rawData = plan['data'];
  final data = Map<String, Object?>.from(
    rawData is String ? jsonDecode(rawData) as Map : rawData as Map,
  );
  final rule = RepeatRule.fromMap(data['recurrence'] as Map?);
  final excluded = data['excludedDates'] as List? ?? const [];
  final dates = repeatOccurrences(
    start: DateTime.parse(plan['date'] as String),
    rule: rule,
    from: from,
    through: through,
    excludedDates: excluded.cast<String>(),
  );
  return dates.map((date) {
    final key = date.toIso8601String().substring(0, 10);
    final override = (data['occurrenceOverrides'] as Map?)?[key] as Map?;
    final occurrenceData = (data['occurrenceData'] as Map?)?[key] as Map?;
    final displayedData = Map<String, Object?>.from(data)
      ..remove('occurrenceData');
    if (occurrenceData != null) {
      displayedData.addAll(Map<String, Object?>.from(occurrenceData));
    }
    return <String, Object?>{
      ...plan,
      if (override != null) ...Map<String, Object?>.from(override),
      'id': '${plan['id']}@$key',
      'seriesId': plan['id'],
      'date': key,
      'data': jsonEncode(displayedData),
      'seriesData': plan['data'],
      'seriesStartDate': plan['date'],
      'isOccurrence': true,
    };
  }).toList();
}
