import 'models.dart';
import 'nutrition_validation.dart';

class WeeklyCaloriesDay {
  const WeeklyCaloriesDay({
    required this.date,
    required this.hasEntries,
    required this.hasValidEntries,
    required this.needsReview,
    required this.kcal,
    required this.isFuture,
  });

  final DateTime date;
  final bool hasEntries;
  final bool hasValidEntries;
  final bool needsReview;
  final double kcal;
  final bool isFuture;
  bool get hasLoggedCalories => hasValidEntries;
}

class WeeklyCaloriesSummary {
  const WeeklyCaloriesSummary({
    required this.days,
    required this.totalKcal,
    required this.averageKcal,
    required this.loggedDayCount,
    required this.belowTarget,
    required this.atTarget,
    required this.aboveTarget,
    required this.targetForLoggedDays,
  });

  final List<WeeklyCaloriesDay> days;
  final double totalKcal;
  final double? averageKcal;
  final int loggedDayCount;
  final int belowTarget;
  final int atTarget;
  final int aboveTarget;
  final double targetForLoggedDays;
  double get differenceFromTarget => totalKcal - targetForLoggedDays;
}

DateTime mondayOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

WeeklyCaloriesSummary summarizeWeeklyCalories({
  required List<FoodEntry> entries,
  required DateTime monday,
  required DateTime today,
  required double dailyTarget,
}) {
  final start = mondayOfWeek(monday);
  final localToday = DateTime(today.year, today.month, today.day);
  final days = <WeeklyCaloriesDay>[];
  var total = 0.0;
  var logged = 0;
  var below = 0;
  var at = 0;
  var above = 0;
  for (var i = 0; i < 7; i++) {
    final date = start.add(Duration(days: i));
    final dateKey = dayKey(date);
    final rows = entries.where((entry) => entry.date == dateKey).toList();
    final valid = rows.where(usableFoodEntryNutrition).toList();
    final kcal = valid.fold<double>(0, (sum, row) => sum + row.total.kcal);
    final hasValid = valid.isNotEmpty;
    final isFuture = date.isAfter(localToday);
    days.add(
      WeeklyCaloriesDay(
        date: date,
        hasEntries: rows.isNotEmpty,
        hasValidEntries: valid.isNotEmpty,
        needsReview: rows.any((row) => !usableFoodEntryNutrition(row)),
        kcal: kcal,
        isFuture: isFuture,
      ),
    );
    if (!isFuture && hasValid) {
      logged++;
      total += kcal;
      if ((kcal - dailyTarget).abs() < .5) {
        at++;
      } else if (kcal < dailyTarget) {
        below++;
      } else {
        above++;
      }
    }
  }
  return WeeklyCaloriesSummary(
    days: days,
    totalKcal: total,
    averageKcal: logged == 0 ? null : total / logged,
    loggedDayCount: logged,
    belowTarget: below,
    atTarget: at,
    aboveTarget: above,
    targetForLoggedDays: dailyTarget * logged,
  );
}
