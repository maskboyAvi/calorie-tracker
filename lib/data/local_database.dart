import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/nutrition_validation.dart';

class LocalDatabase {
  LocalDatabase._({this.filename = 'calorie_companion.db'});
  static final LocalDatabase instance = LocalDatabase._();
  LocalDatabase.forTesting(String filename) : this._(filename: filename);

  final String filename;
  Database? _database;
  Future<Database> get database async => _database ??= await _open();

  Future<void> close() async {
    final current = _database;
    _database = null;
    if (current != null) await current.close();
  }

  Future<Database> _open() async => openDatabase(
    p.join(await getDatabasesPath(), filename),
    version: 5,
    onCreate: (db, version) async {
      await db.execute(
        '''CREATE TABLE foods (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, serving REAL NOT NULL, unit TEXT NOT NULL,
        kcal REAL NOT NULL, protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL,
        category TEXT NOT NULL, source TEXT NOT NULL, favourite INTEGER NOT NULL DEFAULT 0,
        nutrition_basis TEXT NOT NULL DEFAULT 'portion', reference_quantity REAL NOT NULL DEFAULT 1)''',
      );
      await db.execute(
        '''CREATE TABLE entries (
        id TEXT PRIMARY KEY, food_id TEXT, name TEXT NOT NULL, date TEXT NOT NULL, meal TEXT NOT NULL,
        quantity REAL NOT NULL, unit TEXT NOT NULL, base_kcal REAL NOT NULL,
        base_protein REAL NOT NULL, base_carbs REAL NOT NULL, base_fat REAL NOT NULL,
        note TEXT NOT NULL DEFAULT '', source TEXT NOT NULL DEFAULT 'Local',
        nutrition_basis TEXT NOT NULL DEFAULT 'serving', original_quantity REAL,
        original_unit TEXT, reference_quantity REAL, reference_unit TEXT,
        reference_kcal REAL, reference_protein REAL, reference_carbs REAL, reference_fat REAL)''',
      );
      await db.execute('CREATE INDEX entries_date ON entries(date)');
      await db.execute(
        'CREATE TABLE weights (id TEXT PRIMARY KEY, date TEXT NOT NULL, kg REAL NOT NULL, note TEXT NOT NULL DEFAULT \'\')',
      );
      await db.execute('CREATE INDEX weights_date ON weights(date)');
      await db.execute('''CREATE TABLE goals (
        id INTEGER PRIMARY KEY CHECK(id=1), height_cm REAL NOT NULL, start_kg REAL NOT NULL,
        target_min_kg REAL NOT NULL, target_max_kg REAL NOT NULL, kcal REAL NOT NULL,
        protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL,
        ai_enabled INTEGER NOT NULL,
        dark_mode INTEGER NOT NULL, weight_unit TEXT NOT NULL)''');
      await db.execute(
        'CREATE TABLE recipes (id TEXT PRIMARY KEY, name TEXT NOT NULL, servings REAL NOT NULL, data TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE saved_meals (id TEXT PRIMARY KEY, name TEXT NOT NULL, data TEXT NOT NULL, favourite INTEGER NOT NULL DEFAULT 0)',
      );
      await db.execute(
        'CREATE TABLE workout_plans (id TEXT PRIMARY KEY, date TEXT NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL, data TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0)',
      );
      await db.execute('CREATE INDEX workout_date ON workout_plans(date)');
      await db.execute(
        'CREATE TABLE workout_logs (id TEXT PRIMARY KEY, date TEXT NOT NULL, name TEXT NOT NULL, data TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0)',
      );
      await db.execute(
        'CREATE TABLE run_logs (id TEXT PRIMARY KEY, date TEXT NOT NULL, distance_km REAL NOT NULL, duration_min REAL NOT NULL, note TEXT NOT NULL DEFAULT \'\')',
      );
      await db.insert('goals', const AppGoals().toMap());
      final foods = _seedFoods();
      for (final food in foods) {
        await db.insert('foods', food.toMap());
      }
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute(
          "ALTER TABLE entries ADD COLUMN nutrition_basis TEXT NOT NULL DEFAULT 'serving'",
        );
      }
      if (oldVersion < 3) {
        await db.execute(
          'ALTER TABLE entries ADD COLUMN original_quantity REAL',
        );
        await db.execute('ALTER TABLE entries ADD COLUMN original_unit TEXT');
        await db.execute(
          'ALTER TABLE entries ADD COLUMN reference_quantity REAL',
        );
        await db.execute('ALTER TABLE entries ADD COLUMN reference_unit TEXT');
        await db.execute('ALTER TABLE entries ADD COLUMN reference_kcal REAL');
        await db.execute(
          'ALTER TABLE entries ADD COLUMN reference_protein REAL',
        );
        await db.execute('ALTER TABLE entries ADD COLUMN reference_carbs REAL');
        await db.execute('ALTER TABLE entries ADD COLUMN reference_fat REAL');
        await db.execute(
          '''CREATE TABLE goals_v3 (
          id INTEGER PRIMARY KEY CHECK(id=1), height_cm REAL NOT NULL, start_kg REAL NOT NULL,
          target_min_kg REAL NOT NULL, target_max_kg REAL NOT NULL, kcal REAL NOT NULL,
          protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL,
          ai_enabled INTEGER NOT NULL, dark_mode INTEGER NOT NULL, weight_unit TEXT NOT NULL)''',
        );
        await db.execute(
          '''INSERT INTO goals_v3
          (id,height_cm,start_kg,target_min_kg,target_max_kg,kcal,protein,carbs,fat,ai_enabled,dark_mode,weight_unit)
          SELECT id,height_cm,start_kg,target_min_kg,target_max_kg,kcal,protein,carbs,fat,ai_enabled,dark_mode,weight_unit FROM goals''',
        );
        await db.execute('DROP TABLE goals');
        await db.execute('ALTER TABLE goals_v3 RENAME TO goals');
        await db.execute('DROP TABLE IF EXISTS ai_usage');
      }
      if (oldVersion < 5) {
        await db.execute(
          '''CREATE TABLE IF NOT EXISTS foods (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, serving REAL NOT NULL, unit TEXT NOT NULL,
          kcal REAL NOT NULL, protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL,
          category TEXT NOT NULL, source TEXT NOT NULL, favourite INTEGER NOT NULL DEFAULT 0,
          nutrition_basis TEXT NOT NULL DEFAULT 'portion', reference_quantity REAL NOT NULL DEFAULT 1)''',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS saved_meals (id TEXT PRIMARY KEY, name TEXT NOT NULL, data TEXT NOT NULL, favourite INTEGER NOT NULL DEFAULT 0)',
        );
        final savedMealColumns = await db.rawQuery(
          'PRAGMA table_info(saved_meals)',
        );
        if (!savedMealColumns.any((column) => column['name'] == 'favourite')) {
          await db.execute(
            'ALTER TABLE saved_meals ADD COLUMN favourite INTEGER NOT NULL DEFAULT 0',
          );
        }
        final foodColumns = await db.rawQuery('PRAGMA table_info(foods)');
        if (!foodColumns.any((column) => column['name'] == 'nutrition_basis')) {
          await db.execute(
            "ALTER TABLE foods ADD COLUMN nutrition_basis TEXT NOT NULL DEFAULT 'portion'",
          );
        }
        if (!foodColumns.any(
          (column) => column['name'] == 'reference_quantity',
        )) {
          await db.execute(
            'ALTER TABLE foods ADD COLUMN reference_quantity REAL NOT NULL DEFAULT 1',
          );
        }
        await db.execute('UPDATE foods SET reference_quantity = serving');
      }
    },
  );

  List<Food> _seedFoods() => [
    Food(
      name: 'Sprouted moong',
      serving: 100,
      unit: 'g',
      category: 'Indian staples',
      source: 'Local reference estimate',
      nutrition: trustedGramFoods['sprouted moong']!,
    ),
    Food(
      name: 'Cucumber',
      serving: 100,
      unit: 'g',
      category: 'Vegetables',
      source: 'Local reference estimate',
      nutrition: trustedGramFoods['cucumber']!,
    ),
    Food(
      name: 'Cooked basmati rice',
      serving: 1,
      unit: 'cup (158 g)',
      category: 'Indian staples',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 205, protein: 4.3, carbs: 45, fat: 0.4),
    ),
    Food(
      name: 'Roti / chapati',
      serving: 1,
      unit: 'medium',
      category: 'Indian staples',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 120, protein: 3.5, carbs: 20, fat: 3),
    ),
    Food(
      name: 'Dal tadka',
      serving: 1,
      unit: 'cup',
      category: 'Indian dishes',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 210, protein: 12, carbs: 30, fat: 5),
    ),
    Food(
      name: 'Idli',
      serving: 1,
      unit: 'piece',
      category: 'South Indian',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 58, protein: 2, carbs: 12, fat: 0.4),
    ),
    Food(
      name: 'Plain dosa',
      serving: 1,
      unit: 'medium',
      category: 'South Indian',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 168, protein: 4, carbs: 28, fat: 4),
    ),
    Food(
      name: 'Paneer',
      serving: 100,
      unit: 'g',
      category: 'Protein',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 265, protein: 18, carbs: 2, fat: 20),
    ),
    Food(
      name: 'Plain curd',
      serving: 1,
      unit: 'cup (245 g)',
      category: 'Dairy',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 149, protein: 8.5, carbs: 11.4, fat: 8),
    ),
    Food(
      name: 'Poha',
      serving: 1,
      unit: 'cup',
      category: 'Indian dishes',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 250, protein: 5, carbs: 42, fat: 7),
    ),
    Food(
      name: 'Upma',
      serving: 1,
      unit: 'cup',
      category: 'Indian dishes',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 220, protein: 6, carbs: 35, fat: 7),
    ),
    Food(
      name: 'Chole',
      serving: 1,
      unit: 'cup',
      category: 'Indian dishes',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 280, protein: 12, carbs: 42, fat: 7),
    ),
    Food(
      name: 'Boiled egg',
      serving: 1,
      unit: 'large',
      category: 'Protein',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 78, protein: 6.3, carbs: 0.6, fat: 5.3),
    ),
    Food(
      name: 'Chicken breast, cooked',
      serving: 100,
      unit: 'g',
      category: 'Protein',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 165, protein: 31, carbs: 0, fat: 3.6),
    ),
    Food(
      name: 'Banana',
      serving: 1,
      unit: 'medium',
      category: 'Fruit',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 105, protein: 1.3, carbs: 27, fat: 0.4),
    ),
    Food(
      name: 'Almonds',
      serving: 28,
      unit: 'g',
      category: 'Nuts',
      source: 'Starter estimate',
      nutrition: const Nutrition(kcal: 164, protein: 6, carbs: 6, fat: 14),
    ),
  ];

  Future<List<Map<String, Object?>>> all(
    String table, {
    String? orderBy,
  }) async => (await database).query(table, orderBy: orderBy);
  Future<List<Map<String, Object?>>> byDate(String table, String date) async =>
      (await database).query(
        table,
        where: 'date = ?',
        whereArgs: [date],
        orderBy: 'rowid DESC',
      );
  Future<List<Map<String, Object?>>> entriesBetween(
    String startDate,
    String endDate,
  ) async => (await database).query(
    'entries',
    where: 'date >= ? AND date <= ?',
    whereArgs: [startDate, endDate],
    orderBy: 'date ASC, rowid ASC',
  );
  Future<void> upsert(String table, Map<String, Object?> values) async =>
      (await database).insert(
        table,
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
  Future<void> delete(String table, String id) async =>
      (await database).delete(table, where: 'id = ?', whereArgs: [id]);

  Future<void> ensureStarterFoods() async {
    final db = await database;
    final rows = await db.query('foods', columns: ['name']);
    final names = rows
        .map((row) => (row['name'] as String).toLowerCase())
        .toSet();
    for (final food in _seedFoods()) {
      if (!names.contains(food.name.toLowerCase())) {
        await db.insert(
          'foods',
          food.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  /// Repair only obviously implausible gram-based snapshots with an exact
  /// trusted local catalogue match. Unknown records stay intact for review.
  Future<int> repairTrustedCorruptEntries() async {
    final db = await database;
    return db.transaction((txn) async {
      var repaired = 0;
      final rows = await txn.query('entries');
      for (final row in rows) {
        final unit = row['unit'] as String;
        final name = row['name'] as String;
        final stored = Nutrition(
          kcal: (row['base_kcal'] as num).toDouble(),
          protein: (row['base_protein'] as num).toDouble(),
          carbs: (row['base_carbs'] as num).toDouble(),
          fat: (row['base_fat'] as num).toDouble(),
        );
        final basis = row['nutrition_basis'] as String? ?? 'serving';
        final quantity = (row['quantity'] as num).toDouble();
        if (!quantity.isFinite || quantity <= 0) continue;
        final total = stored.scale(
          basis == 'per100' ? quantity / 100 : quantity,
        );
        if (plausibleNutrition(
              stored,
              unit: basis == 'per100' ? unit : 'serving',
            ) &&
            plausibleNutrition(total, unit: 'serving')) {
          continue;
        }
        // Older AI review saved mass quantities as generic "serving" rows.
        // Repair these only when the original prompt names this exact food and
        // gives an explicit gram amount beside it.
        final trusted = trustedNutritionFor(name, 'g');
        if (trusted == null) continue;
        var repairedUnit = unit;
        var repairedQuantity = quantity;
        if (basis != 'per100' || unit.toLowerCase() != 'g') {
          final grams = _explicitGramsForFood(
            name,
            row['note'] as String? ?? '',
          );
          if ((row['source'] as String? ?? '').toLowerCase().contains('ai') &&
              grams != null) {
            repairedUnit = 'g';
            repairedQuantity = grams;
          } else if (basis != 'per100' || unit.toLowerCase() != 'g') {
            continue;
          }
        }
        await txn.update(
          'entries',
          {
            'quantity': repairedQuantity,
            'unit': repairedUnit,
            'base_kcal': trusted.kcal,
            'base_protein': trusted.protein,
            'base_carbs': trusted.carbs,
            'base_fat': trusted.fat,
            'nutrition_basis': 'per100',
            'original_quantity': null,
            'original_unit': null,
            'reference_quantity': null,
            'reference_unit': null,
            'reference_kcal': null,
            'reference_protein': null,
            'reference_carbs': null,
            'reference_fat': null,
            'source': 'Repaired from local reference estimate',
            'note':
                '${row['note']} [Nutrition repaired from local catalogue; verify preparation.]',
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        repaired++;
      }
      return repaired;
    });
  }

  Future<List<FoodEntry>> entriesNeedingNutritionReview() async {
    final rows = await (await database).query('entries');
    return rows
        .map(FoodEntry.fromMap)
        .where((entry) => !usableFoodEntryNutrition(entry))
        .toList();
  }

  double? _explicitGramsForFood(String name, String note) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final catalogNames = trustedGramFoods.keys
        .where((key) => normalized == key || normalized.contains(key))
        .toList();
    if (catalogNames.isEmpty) return null;
    final catalogName = catalogNames.first;
    final escaped = RegExp.escape(catalogName);
    final before = RegExp(
      '(\\d+(?:\\.\\d+)?)\\s*(?:g|gm|gms|gram|grams)\\s*(?:of\\s+)?$escaped\\b',
      caseSensitive: false,
    ).firstMatch(note);
    final after = before == null
        ? RegExp(
            '$escaped[^.\\n]{0,24}?(\\d+(?:\\.\\d+)?)\\s*(?:g|gm|gms|gram|grams)\\b',
            caseSensitive: false,
          ).firstMatch(note)
        : null;
    final value = double.tryParse((before ?? after)?.group(1) ?? '');
    return value != null && value > 0 && value <= 2000 ? value : null;
  }

  Future<AppGoals> goals() async {
    final rows = await (await database).query('goals', where: 'id = 1');
    return AppGoals.fromMap(rows.isEmpty ? null : rows.first);
  }

  Future<void> saveGoals(AppGoals goals) async =>
      upsert('goals', goals.toMap());
  Future<String> exportJson() async {
    final db = await database;
    final data = <String, Object?>{
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
    };
    for (final table in [
      'foods',
      'entries',
      'weights',
      'goals',
      'recipes',
      'saved_meals',
      'workout_plans',
      'workout_logs',
      'run_logs',
    ]) {
      data[table] = await db.query(table);
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> restoreJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Unsupported backup format.');
    }
    const tables = [
      'foods',
      'entries',
      'weights',
      'goals',
      'recipes',
      'saved_meals',
      'workout_plans',
      'workout_logs',
      'run_logs',
    ];
    for (final table in tables) {
      if (decoded[table] is! List) {
        throw FormatException('Backup is missing $table.');
      }
    }
    final db = await database;
    await db.transaction((txn) async {
      for (final table in tables) {
        await txn.delete(table);
        for (final row in decoded[table] as List) {
          if (row is Map) {
            final values = Map<String, Object?>.from(row);
            // Older exports included the removed app-owned AI request limit.
            values.remove('daily_ai_limit');
            await txn.insert(
              table,
              values,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    });
  }

  static Map<String, Object?> jsonRow(
    String id,
    String name,
    Map<String, Object?> data,
  ) => {
    'id': id.isEmpty ? const Uuid().v4() : id,
    'name': name,
    'data': jsonEncode(data),
  };
}
