import 'models.dart';

/// Locally trusted starter values, expressed per 100 g unless specified.
const trustedGramFoods = <String, Nutrition>{
  'sprouted moong': Nutrition(kcal: 30, protein: 3, carbs: 6, fat: 0.2),
  'sprouted mung beans': Nutrition(kcal: 30, protein: 3, carbs: 6, fat: 0.2),
  'mung bean sprouts': Nutrition(kcal: 30, protein: 3, carbs: 6, fat: 0.2),
  'cucumber': Nutrition(kcal: 15, protein: 0.7, carbs: 3.6, fat: 0.1),
};

Nutrition? trustedNutritionFor(String name, String unit) {
  if (unit.toLowerCase() != 'g') return null;
  final normalized = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  for (final entry in trustedGramFoods.entries) {
    if (normalized == entry.key || normalized.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

/// kcal/macros must be in kcal and grams, with nutrients per stated basis.
bool plausibleNutrition(Nutrition n, {required String unit}) {
  final values = [n.kcal, n.protein, n.carbs, n.fat];
  if (values.any((v) => !v.isFinite || v < 0)) return false;
  if (n.kcal > 2500 || n.protein > 300 || n.carbs > 300 || n.fat > 300) {
    return false;
  }
  final massBased = const {'g', 'ml'}.contains(unit.toLowerCase());
  if (massBased &&
      (n.kcal > 900 || n.protein > 100 || n.carbs > 100 || n.fat > 100)) {
    return false;
  }
  // A tolerance allows fibre, rounding, and food-specific energy factors.
  final macroEnergy = n.protein * 4 + n.carbs * 4 + n.fat * 9;
  return n.kcal <= macroEnergy * 1.35 + 25 && macroEnergy <= n.kcal * 1.65 + 35;
}

/// Legacy rows that fail plausibility checks remain stored for review but are
/// excluded from derived totals until the user repairs or re-logs them.
bool usableFoodEntryNutrition(FoodEntry entry) {
  if (!entry.hasValidQuantity) return false;
  final basisUnit = entry.originalQuantity != null
      ? 'serving'
      : entry.nutritionBasis == 'per100'
      ? entry.unit
      : 'serving';
  return plausibleNutrition(entry.baseNutrition, unit: basisUnit) &&
      plausibleNutrition(entry.total, unit: 'serving');
}
