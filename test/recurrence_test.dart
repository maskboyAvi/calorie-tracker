import 'package:calorie_tracker/domain/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final from = DateTime(2026, 10, 19); // Monday

  test('daily recurrence respects optional end date', () {
    final days = repeatOccurrences(
      start: from,
      rule: const RepeatRule(
        frequency: RepeatFrequency.daily,
        until: '2026-10-22',
      ),
      from: from,
      through: DateTime(2026, 10, 25),
    );
    expect(days.map((day) => day.day), [19, 20, 21, 22]);
  });

  test('weekly repeats on selected start weekday', () {
    final days = repeatOccurrences(
      start: from,
      rule: const RepeatRule(frequency: RepeatFrequency.weekly),
      from: from,
      through: DateTime(2026, 11, 2),
    );
    expect(days, [
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 26),
      DateTime(2026, 11, 2),
    ]);
  });

  test('weekly weekday selection can differ from series start date', () {
    final days = repeatOccurrences(
      start: from,
      rule: const RepeatRule(frequency: RepeatFrequency.weekly, weekdays: [5]),
      from: from,
      through: DateTime(2026, 10, 30),
    );
    expect(days.map((day) => day.day), [23, 30]);
  });

  test('custom weekdays filter dates and skip cancelled occurrence', () {
    final days = repeatOccurrences(
      start: from,
      rule: const RepeatRule(
        frequency: RepeatFrequency.custom,
        weekdays: [1, 3, 5],
      ),
      from: from,
      through: DateTime(2026, 10, 25),
      excludedDates: const ['2026-10-21'],
    );
    expect(days.map((day) => day.day), [19, 23]);
  });

  test('series expands to stable display-only IDs without duplicate dates', () {
    final series = <String, Object?>{
      'id': 'series-1',
      'date': '2026-10-19',
      'kind': 'Run',
      'name': 'Run',
      'completed': 0,
      'data': '{"recurrence":{"frequency":"daily","weekdays":[],"until":null},"excludedDates":["2026-10-20"]}',
    };
    final expanded = expandPlanSeries(
      series,
      from: from,
      through: DateTime(2026, 10, 22),
    );
    expect(expanded.map((row) => row['id']).toSet().length, expanded.length);
    expect(expanded.map((row) => row['date']), [
      '2026-10-19',
      '2026-10-21',
      '2026-10-22',
    ]);
    expect(expanded.every((row) => row['seriesId'] == 'series-1'), isTrue);
  });
}
