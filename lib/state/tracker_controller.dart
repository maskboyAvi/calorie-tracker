import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/local_database.dart';
import '../domain/models.dart';
import '../domain/nutrition_validation.dart';
import '../domain/recurrence.dart';

class TrackerController extends ChangeNotifier {
  TrackerController(this.db);
  final LocalDatabase db;
  bool ready = false;
  String? lastError;
  AppGoals goals = const AppGoals();
  List<Food> foods = [];
  List<FoodEntry> entries = [];
  List<FoodEntry> historyEntries = [];
  List<FoodEntry> nutritionEntriesNeedingReview = [];
  List<WeightEntry> weights = [];
  List<Map<String, Object?>> recipes = [];
  List<Map<String, Object?>> savedMeals = [];
  List<Map<String, Object?>> workoutPlans = [];
  List<Map<String, Object?>> _storedWorkoutPlans = [];
  List<Map<String, Object?>> workoutLogs = [];
  List<Map<String, Object?>> runLogs = [];
  String selectedDate = dayKey();
  String mealFilter = 'All';

  Future<void> load() async {
    try {
      await db.ensureStarterFoods();
      await db.repairTrustedCorruptEntries();
      goals = await db.goals();
      foods = (await db.all(
        'foods',
        orderBy: 'name COLLATE NOCASE',
      )).map(Food.fromMap).toList();
      entries = (await db.byDate(
        'entries',
        selectedDate,
      )).map(FoodEntry.fromMap).toList();
      historyEntries = (await db.all(
        'entries',
        orderBy: 'rowid DESC',
      )).map(FoodEntry.fromMap).toList();
      nutritionEntriesNeedingReview = await db.entriesNeedingNutritionReview();
      weights = (await db.all(
        'weights',
        orderBy: 'date DESC',
      )).map(WeightEntry.fromMap).toList();
      recipes = await db.all('recipes', orderBy: 'name COLLATE NOCASE');
      savedMeals = await db.all('saved_meals', orderBy: 'name COLLATE NOCASE');
      _storedWorkoutPlans = await db.all('workout_plans', orderBy: 'date DESC');
      workoutLogs = await db.all('workout_logs', orderBy: 'date DESC');
      workoutPlans = _expandWorkoutPlans();
      runLogs = await db.all('run_logs', orderBy: 'date DESC');
      lastError = null;
      ready = true;
    } catch (e) {
      lastError = '$e';
      ready = true;
    }
    notifyListeners();
  }

  List<Map<String, Object?>> _expandWorkoutPlans() {
    final today = DateTime.now();
    final from = DateTime(today.year, today.month, today.day);
    final through = from.add(const Duration(days: 30));
    final result = <Map<String, Object?>>[];
    final completedIds = workoutLogs.map((row) => row['id']).toSet();
    for (final plan in _storedWorkoutPlans) {
      final data = jsonDecode(plan['data'] as String) as Map<String, Object?>;
      final rule = RepeatRule.fromMap(data['recurrence'] as Map?);
      if (rule.frequency == RepeatFrequency.none) {
        result.add(plan);
      } else {
        for (final occurrence in expandPlanSeries(
          plan,
          from: from,
          through: through,
        )) {
          occurrence['completed'] = completedIds.contains(occurrence['id'])
              ? 1
              : 0;
          result.add(occurrence);
        }
      }
    }
    result.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return result;
  }

  Future<void> selectDate(String date) async {
    selectedDate = date;
    await load();
  }

  Future<void> shiftDate(int days) => selectDate(
    dayKey(DateTime.parse(selectedDate).add(Duration(days: days))),
  );

  Nutrition get selectedTotals => entries
      .where(
        (e) =>
            (mealFilter == 'All' || e.meal == mealFilter) &&
            usableFoodEntryNutrition(e),
      )
      .fold(const Nutrition(), (sum, entry) => sum + entry.total);
  Nutrition get dayTotals => entries
      .where(usableFoodEntryNutrition)
      .fold(const Nutrition(), (sum, entry) => sum + entry.total);
  WeightEntry? get latestWeight => weights.isEmpty ? null : weights.first;
  List<WeightEntry> get lastSevenWeightEntries {
    final from = DateTime.now().subtract(const Duration(days: 6));
    return weights
        .where(
          (w) =>
              !DateTime.parse(w.date)
                  .isBefore(DateTime(from.year, from.month, from.day)),
        )
        .toList();
  }

  double? get sevenDayAverage {
    return sevenDayWeightAverage(weights);
  }

  List<FoodEntry> get visibleEntries => entries
      .where((e) => mealFilter == 'All' || e.meal == mealFilter)
      .toList();

  Future<void> setMealFilter(String value) async {
    mealFilter = value;
    notifyListeners();
  }

  Future<void> saveGoals(AppGoals value) async {
    goals = value;
    await db.saveGoals(value);
    notifyListeners();
  }

  Future<void> upsertFood(Food food) async {
    await db.upsert('foods', food.toMap());
    await load();
  }

  Future<void> toggleFavourite(Food food) async => upsertFood(
    Food(
      id: food.id,
      name: food.name,
      serving: food.serving,
      unit: food.unit,
      nutrition: food.nutrition,
      category: food.category,
      source: food.source,
      favourite: !food.favourite,
      nutritionBasis: food.nutritionBasis,
      referenceQuantity: food.referenceQuantity,
    ),
  );
  Future<void> addEntry(FoodEntry entry) async {
    await db.upsert('entries', entry.toMap());
    await load();
  }

  Future<void> deleteEntry(String id) async {
    await db.delete('entries', id);
    await load();
  }

  Future<void> addWeight(WeightEntry entry) async {
    await db.upsert('weights', entry.toMap());
    await load();
  }

  Future<void> deleteWeight(String id) async {
    await db.delete('weights', id);
    await load();
  }

  Future<void> addRecipe(
    String name,
    double servings,
    List<Map<String, Object?>> ingredients,
  ) async {
    final totals = ingredients.fold(
      const Nutrition(),
      (sum, row) =>
          sum +
          Nutrition.fromMap(row).scale((row['quantity'] as num).toDouble()),
    );
    final perServing = Nutrition(
      kcal: totals.kcal / servings,
      protein: totals.protein / servings,
      carbs: totals.carbs / servings,
      fat: totals.fat / servings,
    );
    final normalizedName = name.trim();
    final matches = recipes.where(
      (recipe) =>
          (recipe['name'] as String).toLowerCase() ==
          normalizedName.toLowerCase(),
    );
    final id = matches.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : matches.first['id'] as String;
    final existingFood = foods.where((food) => food.id == 'recipe-$id');
    await db.upsert('recipes', {
      'id': id,
      'name': normalizedName,
      'servings': servings,
      'data': jsonEncode({
        'ingredients': ingredients,
        'totalNutrition': totals.toMap(),
        ...perServing.toMap(),
      }),
    });
    await upsertFood(
      Food(
        id: 'recipe-$id',
        name: normalizedName,
        serving: 1,
        unit: 'serving',
        nutrition: perServing,
        category: 'Recipe',
        source: 'Homemade recipe',
        favourite: existingFood.isNotEmpty && existingFood.first.favourite,
      ),
    );
  }

  Future<void> saveMeal(String name, List<FoodEntry> items) async {
    final rows = items.map((e) => e.toMap()).toList();
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    final existing = savedMeals.where(
      (meal) =>
          (meal['name'] as String).toLowerCase() == normalized.toLowerCase(),
    );
    final id = existing.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : existing.first['id'] as String;
    await db.upsert('saved_meals', {
      'id': id,
      'name': normalized,
      'data': jsonEncode(rows),
      'favourite': existing.isEmpty ? 0 : existing.first['favourite'] ?? 0,
    });
    await load();
  }

  Future<void> updateSavedMeal({
    required String id,
    required String name,
    required List<FoodEntry> items,
  }) async {
    final previous = savedMeals.where((meal) => meal['id'] == id);
    if (previous.isEmpty || name.trim().isEmpty) return;
    await db.upsert('saved_meals', {
      'id': id,
      'name': name.trim(),
      'data': jsonEncode(items.map((item) => item.toMap()).toList()),
      'favourite': previous.first['favourite'] ?? 0,
    });
    await load();
  }

  Future<void> toggleSavedMealFavourite(Map<String, Object?> meal) async {
    await db.upsert('saved_meals', {
      ...meal,
      'favourite': (meal['favourite'] as num? ?? 0) == 1 ? 0 : 1,
    });
    await load();
  }

  Future<void> deleteSavedMeal(String id) async {
    await db.delete('saved_meals', id);
    await load();
  }

  Future<List<FoodEntry>> entriesBetween(
    String startDate,
    String endDate,
  ) async => (await db.entriesBetween(
    startDate,
    endDate,
  )).map(FoodEntry.fromMap).toList();

  Future<void> planWorkout({
    required String id,
    required String date,
    required String kind,
    required String name,
    required Map<String, Object?> data,
    bool completed = false,
  }) async {
    await db.upsert('workout_plans', {
      'id': id,
      'date': date,
      'kind': kind,
      'name': name,
      'data': jsonEncode(data),
      'completed': completed ? 1 : 0,
    });
    await load();
  }

  Future<void> deleteWorkout(String id) async {
    if (id.contains('@')) {
      final seriesId = id.substring(0, id.lastIndexOf('@'));
      final date = id.substring(id.lastIndexOf('@') + 1);
      final series = _storedWorkoutPlans.firstWhere(
        (row) => row['id'] == seriesId,
      );
      final data = jsonDecode(series['data'] as String) as Map<String, dynamic>;
      final excluded =
          (data['excludedDates'] as List? ?? []).cast<String>().toSet()
            ..add(date);
      data['excludedDates'] = excluded.toList();
      await db.upsert('workout_plans', {...series, 'data': jsonEncode(data)});
    } else {
      await db.delete('workout_plans', id);
    }
    await load();
  }

  Future<void> deleteWorkoutSeries(String id) async {
    await db.delete('workout_plans', id);
    await load();
  }

  Future<void> updateWorkoutOccurrence({
    required String occurrenceId,
    required String name,
    required String kind,
    required Map<String, Object?> occurrenceData,
  }) async {
    final split = occurrenceId.lastIndexOf('@');
    final seriesId = occurrenceId.substring(0, split);
    final date = occurrenceId.substring(split + 1);
    final series = _storedWorkoutPlans.firstWhere(
      (row) => row['id'] == seriesId,
    );
    final data = jsonDecode(series['data'] as String) as Map<String, dynamic>;
    final overrides = Map<String, dynamic>.from(
      data['occurrenceOverrides'] as Map? ?? {},
    );
    overrides[date] = {'name': name, 'kind': kind};
    data['occurrenceOverrides'] = overrides;
    final occurrenceDataMap = Map<String, dynamic>.from(
      data['occurrenceData'] as Map? ?? {},
    );
    occurrenceData.remove('recurrence');
    occurrenceData.remove('excludedDates');
    occurrenceDataMap[date] = occurrenceData;
    data['occurrenceData'] = occurrenceDataMap;
    await db.upsert('workout_plans', {...series, 'data': jsonEncode(data)});
    await load();
  }

  Future<void> toggleWorkout(Map<String, Object?> plan) async {
    final completed = (plan['completed'] as num?) != 1;
    if (plan['isOccurrence'] == true) {
      final id = plan['id'] as String;
      if (completed) {
        await db.upsert('workout_logs', {
          'id': id,
          'date': plan['date'],
          'name': plan['name'],
          'data': plan['data'],
          'completed': 1,
        });
      } else {
        await db.delete('workout_logs', id);
      }
      await load();
      return;
    }
    await planWorkout(
      id: plan['id'] as String,
      date: plan['date'] as String,
      kind: plan['kind'] as String,
      name: plan['name'] as String,
      data: jsonDecode(plan['data'] as String) as Map<String, Object?>,
      completed: completed,
    );
    if (completed) {
      await db.upsert('workout_logs', {
        'id': plan['id'],
        'date': plan['date'],
        'name': plan['name'],
        'data': plan['data'],
        'completed': 1,
      });
    }
  }

  Future<void> toggleWorkoutSet(
    Map<String, Object?> plan,
    int exerciseIndex,
    int setIndex,
  ) async {
    final data = jsonDecode(plan['data'] as String) as Map<String, dynamic>;
    final exercises = data['exercises'] as List<dynamic>;
    final exercise = Map<String, dynamic>.from(exercises[exerciseIndex] as Map);
    final sets = (exercise['sets'] as List<dynamic>)
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    final completed = !(sets[setIndex]['completed'] as bool? ?? false);
    sets[setIndex]['completed'] = completed;
    sets[setIndex]['actualReps'] = completed
        ? sets[setIndex]['targetReps']
        : null;
    sets[setIndex]['actualKg'] = completed ? sets[setIndex]['targetKg'] : null;
    exercise['sets'] = sets;
    exercises[exerciseIndex] = exercise;
    data['exercises'] = exercises;
    if (plan['isOccurrence'] == true) {
      final id = plan['id'] as String;
      final split = id.lastIndexOf('@');
      final seriesId = id.substring(0, split);
      final date = id.substring(split + 1);
      final series = _storedWorkoutPlans.firstWhere(
        (row) => row['id'] == seriesId,
      );
      final seriesData =
          jsonDecode(series['data'] as String) as Map<String, dynamic>;
      final occurrences = Map<String, dynamic>.from(
        seriesData['occurrenceData'] as Map? ?? {},
      );
      final isolated = Map<String, dynamic>.from(data)
        ..remove('recurrence')
        ..remove('excludedDates')
        ..remove('occurrenceData')
        ..remove('occurrenceOverrides');
      occurrences[date] = isolated;
      seriesData['occurrenceData'] = occurrences;
      await db.upsert('workout_plans', {
        ...series,
        'data': jsonEncode(seriesData),
      });
      await load();
      return;
    }
    await planWorkout(
      id: plan['id'] as String,
      date: plan['date'] as String,
      kind: plan['kind'] as String,
      name: plan['name'] as String,
      data: data,
      completed: plan['completed'] == 1,
    );
  }

  Future<void> logRun({
    String? id,
    required String date,
    required double distance,
    required double minutes,
    required String note,
  }) async {
    await db.upsert('run_logs', {
      'id': id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      'date': date,
      'distance_km': distance,
      'duration_min': minutes,
      'note': note,
    });
    await load();
  }

  Future<void> deleteRun(String id) async {
    await db.delete('run_logs', id);
    await load();
  }
}
