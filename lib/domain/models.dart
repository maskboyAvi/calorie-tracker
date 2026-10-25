import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class Nutrition {
  const Nutrition({
    this.kcal = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  Nutrition scale(double quantity) => Nutrition(
    kcal: kcal * quantity,
    protein: protein * quantity,
    carbs: carbs * quantity,
    fat: fat * quantity,
  );

  Nutrition operator +(Nutrition other) => Nutrition(
    kcal: kcal + other.kcal,
    protein: protein + other.protein,
    carbs: carbs + other.carbs,
    fat: fat + other.fat,
  );

  Map<String, Object?> toMap() => {
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
  };
  factory Nutrition.fromMap(Map<String, Object?> map) => Nutrition(
    kcal: (map['kcal'] as num?)?.toDouble() ?? 0,
    protein: (map['protein'] as num?)?.toDouble() ?? 0,
    carbs: (map['carbs'] as num?)?.toDouble() ?? 0,
    fat: (map['fat'] as num?)?.toDouble() ?? 0,
  );
}

class Food {
  Food({
    String? id,
    required this.name,
    required this.serving,
    required this.unit,
    required this.nutrition,
    this.category = 'General',
    this.source = 'Custom',
    this.favourite = false,
    this.nutritionBasis = 'portion',
    double? referenceQuantity,
  }) : id = id ?? _uuid.v4(),
       referenceQuantity = referenceQuantity ?? serving;
  final String id;
  final String name;
  final double serving;
  final String unit;
  final Nutrition nutrition;
  final String category;
  final String source;
  final bool favourite;

  /// `portion` stores totals for [referenceQuantity]; `per100` stores values
  /// per 100 g/ml, independent of the amount later added to the diary.
  final String nutritionBasis;
  final double referenceQuantity;
  bool get isMassBased => const {
    'g',
    'gm',
    'gram',
    'grams',
    'ml',
    'milliliter',
    'millilitre',
  }.contains(unit.trim().toLowerCase());
  Nutrition get perHundredNutrition =>
      isMassBased && serving > 0 && nutritionBasis != 'per100'
      ? nutrition.scale(100 / serving)
      : nutrition;
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'serving': serving,
    'unit': unit,
    ...nutrition.toMap(),
    'category': category,
    'source': source,
    'favourite': favourite ? 1 : 0,
    'nutrition_basis': nutritionBasis,
    'reference_quantity': referenceQuantity,
  };
  factory Food.fromMap(Map<String, Object?> m) => Food(
    id: m['id'] as String?,
    name: m['name'] as String,
    serving: (m['serving'] as num?)?.toDouble() ?? 1,
    unit: m['unit'] as String? ?? 'serving',
    nutrition: Nutrition.fromMap(m),
    category: m['category'] as String? ?? 'General',
    source: m['source'] as String? ?? 'Custom',
    favourite: (m['favourite'] as num?) == 1,
    nutritionBasis: m['nutrition_basis'] as String? ?? 'portion',
    referenceQuantity:
        (m['reference_quantity'] as num?)?.toDouble() ??
        (m['serving'] as num?)?.toDouble() ??
        1,
  );
}

class FoodEntry {
  FoodEntry({
    String? id,
    required this.name,
    required this.date,
    required this.meal,
    required this.quantity,
    required this.unit,
    required this.baseNutrition,
    this.note = '',
    this.source = 'Local',
    this.foodId,
    this.nutritionBasis = 'serving',
    this.originalQuantity,
    this.originalUnit,
    this.referenceQuantity,
    this.referenceUnit,
    this.referenceNutrition,
  }) : id = id ?? _uuid.v4();
  final String id;
  final String? foodId;
  final String name;
  final String date;
  final String meal;
  final double quantity;
  final String unit;
  final Nutrition baseNutrition;
  final String note;
  final String source;

  /// New entries store [baseNutrition] as the total for this original
  /// quantity. Null means this is an older row and uses [nutritionBasis].
  final double? originalQuantity;
  final String? originalUnit;

  /// Optional label reference values, as printed on the package.
  final double? referenceQuantity;
  final String? referenceUnit;
  final Nutrition? referenceNutrition;

  /// `per100` means kcal/macros per 100 g/ml; `serving` preserves legacy
  /// serving snapshots and all piece/cup based entries.
  final String nutritionBasis;
  bool get hasValidQuantity {
    if (!quantity.isFinite || quantity <= 0) return false;
    if (originalQuantity == null) return true;
    if (!originalQuantity!.isFinite || originalQuantity! <= 0) return false;
    try {
      quantityRatio(quantity, unit, originalQuantity!, originalUnit ?? unit);
      return true;
    } on ArgumentError {
      return false;
    }
  }

  Nutrition get total {
    if (!hasValidQuantity) return const Nutrition();
    if (originalQuantity != null) {
      return baseNutrition.scale(
        quantityRatio(quantity, unit, originalQuantity!, originalUnit ?? unit),
      );
    }
    return baseNutrition.scale(
      nutritionBasis == 'per100' ? quantity / 100 : quantity,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'food_id': foodId,
    'name': name,
    'date': date,
    'meal': meal,
    'quantity': quantity,
    'unit': unit,
    'base_kcal': baseNutrition.kcal,
    'base_protein': baseNutrition.protein,
    'base_carbs': baseNutrition.carbs,
    'base_fat': baseNutrition.fat,
    'note': note,
    'source': source,
    'nutrition_basis': nutritionBasis,
    'original_quantity': originalQuantity,
    'original_unit': originalUnit,
    'reference_quantity': referenceQuantity,
    'reference_unit': referenceUnit,
    'reference_kcal': referenceNutrition?.kcal,
    'reference_protein': referenceNutrition?.protein,
    'reference_carbs': referenceNutrition?.carbs,
    'reference_fat': referenceNutrition?.fat,
  };
  factory FoodEntry.fromMap(Map<String, Object?> m) => FoodEntry(
    id: m['id'] as String?,
    foodId: m['food_id'] as String?,
    name: m['name'] as String,
    date: m['date'] as String,
    meal: m['meal'] as String? ?? 'Snack',
    quantity: (m['quantity'] as num).toDouble(),
    unit: m['unit'] as String? ?? 'serving',
    baseNutrition: Nutrition(
      kcal: (m['base_kcal'] as num).toDouble(),
      protein: (m['base_protein'] as num).toDouble(),
      carbs: (m['base_carbs'] as num).toDouble(),
      fat: (m['base_fat'] as num).toDouble(),
    ),
    note: m['note'] as String? ?? '',
    source: m['source'] as String? ?? 'Local',
    nutritionBasis: m['nutrition_basis'] as String? ?? 'serving',
    originalQuantity: (m['original_quantity'] as num?)?.toDouble(),
    originalUnit: m['original_unit'] as String?,
    referenceQuantity: (m['reference_quantity'] as num?)?.toDouble(),
    referenceUnit: m['reference_unit'] as String?,
    referenceNutrition: m['reference_kcal'] is num
        ? Nutrition(
            kcal: (m['reference_kcal'] as num).toDouble(),
            protein: (m['reference_protein'] as num?)?.toDouble() ?? 0,
            carbs: (m['reference_carbs'] as num?)?.toDouble() ?? 0,
            fat: (m['reference_fat'] as num?)?.toDouble() ?? 0,
          )
        : null,
  );
}

/// Creates independent diary snapshots from a saved meal template. The
/// template's current approved totals become the baseline for the new portion;
/// later template edits cannot rewrite diary history.
List<FoodEntry> savedMealDiaryEntries(
  List<FoodEntry> template, {
  required String date,
  required double portions,
}) {
  if (!portions.isFinite || portions <= 0) {
    throw ArgumentError('Portions must be finite and greater than zero.');
  }
  return template
      .map(
        (item) => FoodEntry(
          foodId: item.foodId,
          name: item.name,
          date: date,
          meal: item.meal,
          quantity: item.quantity * portions,
          unit: item.unit,
          baseNutrition: item.total,
          nutritionBasis: 'portion',
          originalQuantity: item.quantity,
          originalUnit: item.unit,
          note: item.note,
          source: item.source,
        ),
      )
      .toList();
}

/// Returns current amount / baseline amount after converting compatible units.
/// Unknown or dimensionally incompatible units are rejected instead of guessed.
double quantityRatio(
  double current,
  String currentUnit,
  double baseline,
  String baselineUnit,
) {
  if (!current.isFinite ||
      current <= 0 ||
      !baseline.isFinite ||
      baseline <= 0) {
    throw ArgumentError('Quantities must be finite and greater than zero.');
  }
  final currentMeasure = _measure(currentUnit);
  final baselineMeasure = _measure(baselineUnit);
  if (currentMeasure == null ||
      baselineMeasure == null ||
      currentMeasure.$1 != baselineMeasure.$1) {
    throw ArgumentError('Quantity units are incompatible.');
  }
  return current * currentMeasure.$2 / (baseline * baselineMeasure.$2);
}

(String, double)? _measure(String unit) {
  switch (unit.trim().toLowerCase()) {
    case 'g':
    case 'gm':
    case 'gram':
    case 'grams':
      return ('mass', 1);
    case 'kg':
    case 'kilogram':
    case 'kilograms':
      return ('mass', 1000);
    case 'mg':
    case 'milligram':
    case 'milligrams':
      return ('mass', .001);
    case 'ml':
    case 'milliliter':
    case 'milliliters':
    case 'millilitre':
    case 'millilitres':
      return ('volume', 1);
    case 'l':
    case 'liter':
    case 'liters':
    case 'litre':
    case 'litres':
      return ('volume', 1000);
    case 'serving':
    case 'servings':
    case 'portion':
    case 'portions':
      return ('serving', 1);
    case 'piece':
    case 'pieces':
      return ('piece', 1);
    case 'cup':
    case 'cups':
      return ('cup', 1);
    case 'bowl':
    case 'bowls':
      return ('bowl', 1);
    case 'slice':
    case 'slices':
      return ('slice', 1);
    case 'tbsp':
    case 'tablespoon':
    case 'tablespoons':
      return ('tbsp', 1);
    case 'tsp':
    case 'teaspoon':
    case 'teaspoons':
      return ('tsp', 1);
    case 'pack':
    case 'packs':
      return ('pack', 1);
    default:
      final custom = unit.trim().toLowerCase();
      return custom.isEmpty ? null : (custom, 1);
  }
}

class WeightEntry {
  WeightEntry({
    String? id,
    required this.date,
    required this.kg,
    this.note = '',
  }) : id = id ?? _uuid.v4();
  final String id;
  final String date;
  final double kg;
  final String note;
  Map<String, Object?> toMap() => {
    'id': id,
    'date': date,
    'kg': kg,
    'note': note,
  };
  factory WeightEntry.fromMap(Map<String, Object?> m) => WeightEntry(
    id: m['id'] as String?,
    date: m['date'] as String,
    kg: (m['kg'] as num).toDouble(),
    note: m['note'] as String? ?? '',
  );
}

class AppGoals {
  const AppGoals({
    this.heightCm = 175,
    this.startKg = 84,
    this.targetMinKg = 77,
    this.targetMaxKg = 78,
    this.kcal = 2100,
    this.protein = 150,
    this.carbs = 0,
    this.fat = 0,
    this.aiEnabled = false,
    this.darkMode = false,
    this.weightUnit = 'kg',
  });
  final double heightCm,
      startKg,
      targetMinKg,
      targetMaxKg,
      kcal,
      protein,
      carbs,
      fat;
  final bool aiEnabled, darkMode;
  final String weightUnit;
  AppGoals copyWith({
    double? heightCm,
    double? startKg,
    double? targetMinKg,
    double? targetMaxKg,
    double? kcal,
    double? protein,
    double? carbs,
    double? fat,
    bool? aiEnabled,
    bool? darkMode,
    String? weightUnit,
  }) => AppGoals(
    heightCm: heightCm ?? this.heightCm,
    startKg: startKg ?? this.startKg,
    targetMinKg: targetMinKg ?? this.targetMinKg,
    targetMaxKg: targetMaxKg ?? this.targetMaxKg,
    kcal: kcal ?? this.kcal,
    protein: protein ?? this.protein,
    carbs: carbs ?? this.carbs,
    fat: fat ?? this.fat,
    aiEnabled: aiEnabled ?? this.aiEnabled,
    darkMode: darkMode ?? this.darkMode,
    weightUnit: weightUnit ?? this.weightUnit,
  );
  Map<String, Object?> toMap() => {
    'id': 1,
    'height_cm': heightCm,
    'start_kg': startKg,
    'target_min_kg': targetMinKg,
    'target_max_kg': targetMaxKg,
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'ai_enabled': aiEnabled ? 1 : 0,
    'dark_mode': darkMode ? 1 : 0,
    'weight_unit': weightUnit,
  };
  factory AppGoals.fromMap(Map<String, Object?>? m) => m == null
      ? const AppGoals()
      : AppGoals(
          heightCm: (m['height_cm'] as num).toDouble(),
          startKg: (m['start_kg'] as num).toDouble(),
          targetMinKg: (m['target_min_kg'] as num).toDouble(),
          targetMaxKg: (m['target_max_kg'] as num).toDouble(),
          kcal: (m['kcal'] as num).toDouble(),
          protein: (m['protein'] as num).toDouble(),
          carbs: (m['carbs'] as num).toDouble(),
          fat: (m['fat'] as num).toDouble(),
          aiEnabled: (m['ai_enabled'] as num) == 1,
          darkMode: (m['dark_mode'] as num) == 1,
          weightUnit: m['weight_unit'] as String,
        );
}

String dayKey([DateTime? date]) {
  final d = date ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

double? sevenDayWeightAverage(List<WeightEntry> weights, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final start = DateTime(
    current.year,
    current.month,
    current.day,
  ).subtract(const Duration(days: 6));
  final end = DateTime(
    current.year,
    current.month,
    current.day,
  ).add(const Duration(days: 1));
  final daily = <String, double>{};
  for (final weight in weights) {
    final date = DateTime.parse(weight.date);
    if (!date.isBefore(start) && date.isBefore(end)) {
      daily[weight.date] = weight.kg;
    }
  }
  if (daily.isEmpty) return null;
  return daily.values.reduce((a, b) => a + b) / daily.length;
}
