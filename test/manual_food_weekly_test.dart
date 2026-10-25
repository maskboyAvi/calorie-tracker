import 'package:calorie_tracker/data/local_database.dart';
import 'package:calorie_tracker/domain/models.dart';
import 'package:calorie_tracker/domain/weekly_calories.dart';
import 'package:calorie_tracker/state/tracker_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('manual food nutrition bases', () {
    test('database migration retains older food and saved-meal rows', () async {
      const filename = 'manual_food_v4_migration_test.db';
      final path = '${await databaseFactory.getDatabasesPath()}/$filename';
      await databaseFactory.deleteDatabase(path);
      final old = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) async {
            await db.execute(
              '''CREATE TABLE foods (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, serving REAL NOT NULL, unit TEXT NOT NULL,
              kcal REAL NOT NULL, protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL,
              category TEXT NOT NULL, source TEXT NOT NULL, favourite INTEGER NOT NULL DEFAULT 0)''',
            );
            await db.execute(
              'CREATE TABLE saved_meals (id TEXT PRIMARY KEY, name TEXT NOT NULL, data TEXT NOT NULL)',
            );
            await db.insert('foods', {
              'id': 'old-food',
              'name': 'Old rice',
              'serving': 1,
              'unit': 'cup',
              'kcal': 200,
              'protein': 4,
              'carbs': 45,
              'fat': 1,
              'category': 'Custom',
              'source': 'Custom',
              'favourite': 1,
            });
            await db.insert('saved_meals', {
              'id': 'old-meal',
              'name': 'Old meal',
              'data': '[]',
            });
          },
        ),
      );
      await old.close();

      final migrated = LocalDatabase.forTesting(filename);
      final food = (await migrated.all('foods')).single;
      final meal = (await migrated.all('saved_meals')).single;
      expect(food['name'], 'Old rice');
      expect(food['kcal'], 200);
      expect(food['reference_quantity'], 1);
      expect(food['nutrition_basis'], 'portion');
      expect(meal['name'], 'Old meal');
      expect(meal['favourite'], 0);
      await migrated.close();
      await databaseFactory.deleteDatabase(path);
    });

    test('amount eaten stores totals and later scales from that baseline', () {
      final food = Food(
        name: 'Cooked rice',
        serving: 200,
        unit: 'g',
        nutrition: const Nutrition(kcal: 260, protein: 5, carbs: 56, fat: .6),
        nutritionBasis: 'portion',
        referenceQuantity: 200,
      );
      final entry = FoodEntry(
        foodId: food.id,
        name: food.name,
        date: '2026-10-19',
        meal: 'Lunch',
        quantity: 200,
        unit: 'g',
        baseNutrition: food.nutrition.scale(
          quantityRatio(200, 'g', food.serving, food.unit),
        ),
        originalQuantity: 200,
        originalUnit: 'g',
      );
      expect(entry.total.kcal, 260);
      expect(entry.total.protein, 5);
      final edited = FoodEntry(
        name: entry.name,
        date: entry.date,
        meal: entry.meal,
        quantity: 100,
        unit: 'g',
        baseNutrition: entry.baseNutrition,
        originalQuantity: entry.originalQuantity,
        originalUnit: entry.originalUnit,
      );
      expect(edited.total.kcal, 130);
      expect(edited.total.carbs, 28);
    });

    test('per 100 g food scales 200 g by exactly two', () {
      final food = Food(
        name: 'Cooked rice',
        serving: 100,
        unit: 'g',
        nutrition: const Nutrition(kcal: 130, protein: 2.5, carbs: 28, fat: .3),
        nutritionBasis: 'per100',
        referenceQuantity: 100,
      );
      expect(food.perHundredNutrition.kcal, 130);
      final entry = FoodEntry(
        name: food.name,
        date: '2026-10-19',
        meal: 'Lunch',
        quantity: 200,
        unit: 'g',
        baseNutrition: food.nutrition.scale(2),
        originalQuantity: 200,
        originalUnit: 'g',
      );
      expect(entry.total.kcal, 260);
      expect(entry.total.carbs, 56);
    });

    test('persists a custom food basis and reference amount', () async {
      const filename = 'manual_food_basis_test.db';
      final path = '${await databaseFactory.getDatabasesPath()}/$filename';
      await databaseFactory.deleteDatabase(path);
      final db = LocalDatabase.forTesting(filename);
      final food = Food(
        name: 'Test custom',
        serving: 200,
        unit: 'ml',
        nutrition: const Nutrition(kcal: 80, protein: 3, carbs: 10, fat: 2),
        nutritionBasis: 'portion',
        referenceQuantity: 200,
      );
      await db.upsert('foods', food.toMap());
      final restored = Food.fromMap(
        (await db.all('foods')).singleWhere((row) => row['id'] == food.id),
      );
      expect(restored.nutritionBasis, 'portion');
      expect(restored.referenceQuantity, 200);
      expect(restored.nutrition.kcal, food.nutrition.kcal);
      expect(restored.nutrition.protein, food.nutrition.protein);
      expect(restored.nutrition.carbs, food.nutrition.carbs);
      expect(restored.nutrition.fat, food.nutrition.fat);
      await db.close();
      await databaseFactory.deleteDatabase(path);
    });
  });

  test('saved meal reuse scales independently and retains diary history', () {
    final original = FoodEntry(
      id: 'history-row',
      name: 'Dal',
      date: '2026-10-18',
      meal: 'Lunch',
      quantity: 1,
      unit: 'bowl',
      baseNutrition: const Nutrition(kcal: 220, protein: 12, carbs: 30, fat: 6),
      originalQuantity: 1,
      originalUnit: 'bowl',
    );
    final reused = savedMealDiaryEntries(
      [original],
      date: '2026-10-19',
      portions: 1.5,
    );
    expect(reused.single.id, isNot(original.id));
    expect(reused.single.date, '2026-10-19');
    expect(reused.single.quantity, 1.5);
    expect(reused.single.total.kcal, 330);
    expect(original.total.kcal, 220);
    expect(
      savedMealDiaryEntries(
        [original],
        date: '2026-10-19',
        portions: 1,
      ).single.id,
      isNot(reused.single.id),
    );
  });

  test(
    'weekly summary follows Monday boundaries and excludes missing days',
    () {
      final monday = DateTime(2026, 10, 26);
      final entries = [
        FoodEntry(
          name: 'Day one',
          date: '2026-10-26',
          meal: 'Lunch',
          quantity: 1,
          unit: 'serving',
          baseNutrition: const Nutrition(
            kcal: 2100,
            protein: 100,
            carbs: 262.5,
            fat: 70,
          ),
          originalQuantity: 1,
        ),
        FoodEntry(
          name: 'Day two',
          date: '2026-10-27',
          meal: 'Lunch',
          quantity: 1,
          unit: 'serving',
          baseNutrition: const Nutrition(
            kcal: 1800,
            protein: 90,
            carbs: 225,
            fat: 60,
          ),
          originalQuantity: 1,
        ),
        FoodEntry(
          name: 'Confirmed zero day',
          date: '2026-10-28',
          meal: 'Lunch',
          quantity: 1,
          unit: 'serving',
          baseNutrition: const Nutrition(),
          originalQuantity: 1,
        ),
      ];
      final summary = summarizeWeeklyCalories(
        entries: entries,
        monday: monday,
        today: DateTime(2026, 10, 29),
        dailyTarget: 2000,
      );
      expect(summary.days.map((day) => day.date.weekday), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
      expect(summary.days.first.kcal, 2100);
      expect(summary.days[2].needsReview, isFalse);
      expect(summary.days[2].hasEntries, isTrue);
      expect(summary.days[2].kcal, 0);
      expect(summary.days[3].hasEntries, isFalse);
      expect(summary.totalKcal, 3900);
      expect(summary.averageKcal, 1300);
      expect(summary.loggedDayCount, 3);
      expect(summary.aboveTarget, 1);
      expect(summary.belowTarget, 2);
      expect(summary.targetForLoggedDays, 6000);
      expect(summary.days[4].isFuture, isTrue);
    },
  );

  test('saved meal favorite and edit only mutate reusable template', () async {
    const filename = 'saved_meal_edit_test.db';
    final path = '${await databaseFactory.getDatabasesPath()}/$filename';
    await databaseFactory.deleteDatabase(path);
    final controller = TrackerController(LocalDatabase.forTesting(filename));
    await controller.load();
    final history = FoodEntry(
      id: 'unchanged-diary',
      name: 'Dal',
      date: '2026-10-18',
      meal: 'Lunch',
      quantity: 1,
      unit: 'bowl',
      baseNutrition: const Nutrition(kcal: 220, protein: 12, carbs: 30, fat: 6),
      originalQuantity: 1,
      originalUnit: 'bowl',
    );
    await controller.addEntry(history);
    await controller.saveMeal('Dal lunch', [history]);
    var saved = controller.savedMeals.single;
    await controller.toggleSavedMealFavourite(saved);
    saved = controller.savedMeals.single;
    expect(saved['favourite'], 1);
    final editedItem = FoodEntry(
      id: history.id,
      name: 'Dal corrected',
      date: history.date,
      meal: history.meal,
      quantity: 1,
      unit: 'bowl',
      baseNutrition: const Nutrition(kcal: 200),
      originalQuantity: 1,
      originalUnit: 'bowl',
    );
    await controller.updateSavedMeal(
      id: saved['id'] as String,
      name: 'Updated dal',
      items: [editedItem],
    );
    expect(controller.savedMeals.single['name'], 'Updated dal');
    final persistedHistory = FoodEntry.fromMap(
      (await controller.db.byDate('entries', history.date)).single,
    );
    expect(persistedHistory.name, 'Dal');
    expect(persistedHistory.total.kcal, 220);
    await controller.deleteSavedMeal(saved['id'] as String);
    expect(controller.savedMeals, isEmpty);
    await controller.db.close();
    await databaseFactory.deleteDatabase(path);
  });

  test(
    'replacing a same-name recipe updates its template without duplicates',
    () async {
      const filename = 'saved_recipe_update_test.db';
      final path = '${await databaseFactory.getDatabasesPath()}/$filename';
      await databaseFactory.deleteDatabase(path);
      final controller = TrackerController(LocalDatabase.forTesting(filename));
      await controller.load();
      await controller.addRecipe('Home dal', 2, [
        {
          'quantity': 2,
          'kcal': 220,
          'protein': 12,
          'carbs': 30,
          'fat': 6,
          'food_name': 'Dal',
        },
      ]);
      final firstId = controller.recipes.single['id'];
      expect(
        controller.foods.where((food) => food.id == 'recipe-$firstId').length,
        1,
      );
      await controller.addRecipe('Home dal', 1, [
        {
          'quantity': 1,
          'kcal': 180,
          'protein': 10,
          'carbs': 22,
          'fat': 4,
          'food_name': 'Dal',
        },
      ]);
      expect(controller.recipes.length, 1);
      expect(controller.recipes.single['id'], firstId);
      expect(
        controller.foods.where((food) => food.id == 'recipe-$firstId').length,
        1,
      );
      expect(
        controller.foods
            .singleWhere((food) => food.id == 'recipe-$firstId')
            .nutrition
            .kcal,
        180,
      );
      await controller.db.close();
      await databaseFactory.deleteDatabase(path);
    },
  );
}
