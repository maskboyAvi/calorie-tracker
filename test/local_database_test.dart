import 'dart:convert';

import 'package:calorie_tracker/data/local_database.dart';
import 'package:calorie_tracker/domain/models.dart';
import 'package:calorie_tracker/domain/nutrition_validation.dart';
import 'package:calorie_tracker/domain/recurrence.dart';
import 'package:calorie_tracker/state/tracker_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final file =
        '${await databaseFactory.getDatabasesPath()}/calorie_companion.db';
    await databaseFactory.deleteDatabase(file);
  });

  test(
    'persists food snapshots, goals, weight and workout plans; backup restores',
    () async {
      final db = LocalDatabase.instance;
      final food = Food(
        name: 'Test dal',
        serving: 1,
        unit: 'cup',
        nutrition: const Nutrition(kcal: 200, protein: 10, carbs: 25, fat: 5),
      );
      await db.upsert('foods', food.toMap());
      final entry = FoodEntry(
        foodId: food.id,
        name: food.name,
        date: '2026-10-17',
        meal: 'Lunch',
        quantity: 1.5,
        unit: 'cup',
        baseNutrition: food.nutrition,
      );
      await db.upsert('entries', entry.toMap());
      await db.upsert(
        'weights',
        WeightEntry(date: '2026-10-17', kg: 83.5).toMap(),
      );
      await db.upsert('workout_plans', {
        'id': 'session-1',
        'date': '2026-10-17',
        'kind': 'Gym',
        'name': 'Upper body',
        'data': jsonEncode({
          'recurrence': const RepeatRule(
            frequency: RepeatFrequency.custom,
            weekdays: [1, 3, 5],
            until: '2026-12-31',
          ).toMap(),
          'exercises': [
            {
              'name': 'Row',
              'sets': [
                {'completed': false},
              ],
            },
          ],
        }),
        'completed': 0,
      });

      final storedEntry = FoodEntry.fromMap(
        (await db.byDate('entries', '2026-10-17')).single,
      );
      expect(storedEntry.total.kcal, 300);
      expect(storedEntry.total.protein, 15);
      expect((await db.all('workout_plans')).single['name'], 'Upper body');
      final storedPlan = (await db.all('workout_plans')).single;
      final storedRule = RepeatRule.fromMap(
        (jsonDecode(storedPlan['data'] as String) as Map)['recurrence'] as Map,
      );
      expect(storedRule.weekdays, [1, 3, 5]);
      expect(storedRule.until, '2026-12-31');
      final persistedOccurrences = expandPlanSeries(
        storedPlan,
        from: DateTime(2026, 10, 17),
        through: DateTime(2026, 10, 23),
      );
      expect(persistedOccurrences.map((row) => row['date']), [
        '2026-10-19',
        '2026-10-21',
        '2026-10-23',
      ]);

      final moong = FoodEntry(
        name: 'Sprouted moong',
        date: '2026-10-17',
        meal: 'Lunch',
        quantity: 200,
        unit: 'g',
        baseNutrition: trustedGramFoods['sprouted moong']!,
        nutritionBasis: 'per100',
      );
      final cucumber = FoodEntry(
        name: 'Cucumber',
        date: '2026-10-17',
        meal: 'Lunch',
        quantity: 150,
        unit: 'g',
        baseNutrition: trustedGramFoods['cucumber']!,
        nutritionBasis: 'per100',
      );
      await db.upsert('entries', moong.toMap());
      await db.upsert('entries', cucumber.toMap());
      final dailyEntries = (await db.byDate(
        'entries',
        '2026-10-17',
      )).map(FoodEntry.fromMap).toList();
      final dashboardTotal = dailyEntries.fold(
        const Nutrition(),
        (total, row) => total + row.total,
      );
      expect(dashboardTotal.kcal, closeTo(382.5, .001));
      // 300 kcal from the existing 1.5-cup dal + 82.5 kcal from the gram foods.
      final corrupt = FoodEntry(
        id: 'known-corrupt',
        name: 'Sprouted moong',
        date: '2026-10-17',
        meal: 'Lunch',
        quantity: 200,
        unit: 'g',
        baseNutrition: const Nutrition(
          kcal: 42000,
          protein: 2800,
          carbs: 7600,
          fat: 200,
        ),
        nutritionBasis: 'per100',
      );
      await db.upsert('entries', corrupt.toMap());
      expect(await db.repairTrustedCorruptEntries(), 1);
      final repaired = FoodEntry.fromMap(
        (await db.byDate(
          'entries',
          '2026-10-17',
        )).singleWhere((row) => row['id'] == 'known-corrupt'),
      );
      expect(repaired.total.kcal, 60);
      expect(repaired.quantity, 200);
      final legacyAiRow = FoodEntry(
        id: 'legacy-ai-corrupt',
        name: 'Sprouted moong',
        date: '2026-10-17',
        meal: 'Lunch',
        quantity: 200,
        unit: 'serving',
        baseNutrition: const Nutrition(
          kcal: 210,
          protein: 14,
          carbs: 38,
          fat: 1,
        ),
        note: '200 gm sprouted moong with 150 gm cucumber and lemon and salt.',
        source: 'AI estimate',
      );
      await db.upsert('entries', legacyAiRow.toMap());
      expect(await db.repairTrustedCorruptEntries(), 1);
      final migratedLegacy = FoodEntry.fromMap(
        (await db.byDate(
          'entries',
          '2026-10-17',
        )).singleWhere((row) => row['id'] == 'legacy-ai-corrupt'),
      );
      expect(migratedLegacy.unit, 'g');
      expect(migratedLegacy.nutritionBasis, 'per100');
      expect(migratedLegacy.total.kcal, 60);
      final unknownCorrupt = FoodEntry(
        id: 'unknown-corrupt',
        name: 'Uncatalogued food',
        date: '2026-10-17',
        meal: 'Lunch',
        quantity: 150,
        unit: 'g',
        baseNutrition: const Nutrition(
          kcal: 3450,
          protein: 150,
          carbs: 750,
          fat: 30,
        ),
        nutritionBasis: 'per100',
      );
      await db.upsert('entries', unknownCorrupt.toMap());
      expect(await db.repairTrustedCorruptEntries(), 0);
      expect(
        (await db.entriesNeedingNutritionReview()).map((e) => e.id),
        contains('unknown-corrupt'),
      );
      expect(
        (await db.byDate(
          'entries',
          '2026-10-17',
        )).any((row) => row['id'] == 'unknown-corrupt'),
        isTrue,
      );

      final backup = await db.exportJson();
      await db.delete('entries', entry.id);
      await db.restoreJson(backup);
      expect((await db.byDate('entries', '2026-10-17')).length, 6);
      expect((await db.all('weights')).single['kg'], 83.5);
      expect((await db.all('workout_plans')).single['id'], 'session-1');
      expect(() => db.restoreJson('{"version":99}'), throwsFormatException);
    },
  );

  test(
    'recurring occurrence edits and cancellations do not duplicate plans',
    () async {
      final db = LocalDatabase.instance;
      final tracker = TrackerController(db);
      final start = DateTime.now();
      final today = DateTime(start.year, start.month, start.day);
      final todayKey = dayKey(today);
      final tomorrowKey = dayKey(today.add(const Duration(days: 1)));
      await tracker.planWorkout(
        id: 'recurring-smoke',
        date: todayKey,
        kind: 'Run',
        name: 'Easy run',
        data: {
          'goals': {'distance': 3},
          'recurrence': RepeatRule(
            frequency: RepeatFrequency.daily,
            until: tomorrowKey,
          ).toMap(),
        },
      );
      final seriesRows = tracker.workoutPlans
          .where((row) => row['seriesId'] == 'recurring-smoke')
          .toList();
      expect(seriesRows.map((row) => row['date']), [todayKey, tomorrowKey]);
      expect(
        (await db.all('workout_plans'))
            .where((row) => row['id'] == 'recurring-smoke')
            .length,
        1,
      );

      await tracker.deleteWorkout('recurring-smoke@$todayKey');
      expect(
        tracker.workoutPlans.any(
          (row) =>
              row['date'] == todayKey && row['seriesId'] == 'recurring-smoke',
        ),
        isFalse,
      );
      expect(
        tracker.workoutPlans.any(
          (row) =>
              row['date'] == tomorrowKey &&
              row['seriesId'] == 'recurring-smoke',
        ),
        isTrue,
      );

      await tracker.updateWorkoutOccurrence(
        occurrenceId: 'recurring-smoke@$tomorrowKey',
        name: 'Longer run',
        kind: 'Run',
        occurrenceData: {
          'goals': {'distance': 5},
        },
      );
      final tomorrow = tracker.workoutPlans.singleWhere(
        (row) =>
            row['date'] == tomorrowKey && row['seriesId'] == 'recurring-smoke',
      );
      expect(tomorrow['name'], 'Longer run');
      await tracker.toggleWorkout(tomorrow);
      expect(
        tracker.workoutPlans.singleWhere(
          (row) => row['id'] == 'recurring-smoke@$tomorrowKey',
        )['completed'],
        1,
      );
      expect(
        (await db.all('workout_logs'))
            .any((row) => row['id'] == 'recurring-smoke@$tomorrowKey'),
        isTrue,
      );
      tracker.dispose();
    },
  );

  test('version 1 diary migrates with legacy serving basis intact', () async {
    const filename = 'calorie_legacy_migration_test.db';
    final path = '${await databaseFactory.getDatabasesPath()}/$filename';
    await databaseFactory.deleteDatabase(path);
    final old = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE entries (
          id TEXT PRIMARY KEY, food_id TEXT, name TEXT NOT NULL, date TEXT NOT NULL,
          meal TEXT NOT NULL, quantity REAL NOT NULL, unit TEXT NOT NULL,
          base_kcal REAL NOT NULL, base_protein REAL NOT NULL, base_carbs REAL NOT NULL,
          base_fat REAL NOT NULL, note TEXT NOT NULL DEFAULT '',
          source TEXT NOT NULL DEFAULT 'Local')''');
        await db.execute('''CREATE TABLE goals (
          id INTEGER PRIMARY KEY, height_cm REAL NOT NULL, start_kg REAL NOT NULL,
          target_min_kg REAL NOT NULL, target_max_kg REAL NOT NULL, kcal REAL NOT NULL,
          protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL,
          daily_ai_limit INTEGER NOT NULL, ai_enabled INTEGER NOT NULL,
          dark_mode INTEGER NOT NULL, weight_unit TEXT NOT NULL)''');
        await db.insert('goals', {
          'id': 1,
          'height_cm': 175,
          'start_kg': 84,
          'target_min_kg': 77,
          'target_max_kg': 78,
          'kcal': 2100,
          'protein': 150,
          'carbs': 0,
          'fat': 0,
          'daily_ai_limit': 5,
          'ai_enabled': 0,
          'dark_mode': 0,
          'weight_unit': 'kg',
        });
      },
    );
    await old.insert('entries', {
      'id': 'legacy',
      'name': 'Banana',
      'date': '2026-10-17',
      'meal': 'Snack',
      'quantity': 1,
      'unit': 'serving',
      'base_kcal': 105,
      'base_protein': 1.3,
      'base_carbs': 27,
      'base_fat': .4,
    });
    await old.close();

    final upgraded = LocalDatabase.forTesting(filename);
    final database = await upgraded.database;
    final entries = await database.query('entries');
    final columns = await database.rawQuery("PRAGMA table_info('entries')");
    expect(columns.map((row) => row['name']), contains('nutrition_basis'));
    final entry = FoodEntry.fromMap(entries.single);
    expect(entry.nutritionBasis, 'serving');
    expect(entry.total.kcal, 105);
    final goalColumns = await database.rawQuery("PRAGMA table_info('goals')");
    expect(
      goalColumns.map((row) => row['name']),
      isNot(contains('daily_ai_limit')),
    );
    await database.close();
    await databaseFactory.deleteDatabase(path);
  });

  test('baseline AI portion persists and rescales after reload', () async {
    const filename = 'calorie_baseline_persistence_test.db';
    final path = '${await databaseFactory.getDatabasesPath()}/$filename';
    await databaseFactory.deleteDatabase(path);
    final db = LocalDatabase.forTesting(filename);
    final original = FoodEntry(
      id: 'rice-portion',
      name: 'Cooked rice',
      date: '2026-10-17',
      meal: 'Lunch',
      quantity: 200,
      unit: 'g',
      originalQuantity: 250,
      originalUnit: 'g',
      nutritionBasis: 'portion',
      baseNutrition: const Nutrition(
        kcal: 325,
        protein: 6.75,
        carbs: 70,
        fat: .7,
      ),
      referenceQuantity: 100,
      referenceUnit: 'g',
      referenceNutrition: const Nutrition(
        kcal: 370,
        protein: 10,
        carbs: 80,
        fat: 2,
      ),
    );
    await db.upsert('entries', original.toMap());
    final stored = FoodEntry.fromMap(
      (await db.byDate('entries', '2026-10-17')).single,
    );
    expect(stored.originalQuantity, 250);
    expect(stored.baseNutrition.kcal, 325);
    expect(stored.referenceQuantity, 100);
    expect(stored.referenceNutrition!.kcal, 370);
    expect(stored.total.kcal, 260);
    final edited = FoodEntry(
      id: stored.id,
      name: stored.name,
      date: stored.date,
      meal: stored.meal,
      quantity: 250,
      unit: stored.unit,
      originalQuantity: stored.originalQuantity,
      originalUnit: stored.originalUnit,
      nutritionBasis: 'portion',
      baseNutrition: stored.baseNutrition,
    );
    await db.upsert('entries', edited.toMap());
    final returned = FoodEntry.fromMap(
      (await db.byDate('entries', '2026-10-17')).single,
    );
    expect(returned.total.kcal, 325);
    final goalsColumns = await (await db.database).rawQuery(
      "PRAGMA table_info('goals')",
    );
    expect(
      goalsColumns.map((row) => row['name']),
      isNot(contains('daily_ai_limit')),
    );
    expect(
      await (await db.database).rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='ai_usage'",
      ),
      isEmpty,
    );
    await (await db.database).close();
    await databaseFactory.deleteDatabase(path);
  });
}
