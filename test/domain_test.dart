import 'dart:async';
import 'dart:io';

import 'package:calorie_tracker/domain/models.dart';
import 'package:calorie_tracker/domain/nutrition_validation.dart';
import 'package:calorie_tracker/services/ai_assistant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nutrition math', () {
    test('scales calories and macros by editable serving quantity', () {
      const base = Nutrition(kcal: 200, protein: 10, carbs: 30, fat: 5);
      final result = base.scale(1.5);
      expect(result.kcal, 300);
      expect(result.protein, 15);
      expect(result.carbs, 45);
      expect(result.fat, 7.5);
    });

    test('adds entry totals deterministically', () {
      const first = Nutrition(kcal: 100, protein: 10);
      const second = Nutrition(kcal: 250, carbs: 40);
      final total = first + second;
      expect(total.kcal, 350);
      expect(total.protein, 10);
      expect(total.carbs, 40);
    });

    test('gram quantities scale per-100-g nutrition by quantity / 100', () {
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
      final day = moong.total + cucumber.total;
      expect(moong.total.kcal, 60);
      expect(cucumber.total.kcal, 22.5);
      expect(day.kcal, 82.5);
      expect(day.protein, closeTo(7.05, .001));
      expect(day.carbs, closeTo(17.4, .001));
      expect(day.fat, closeTo(.55, .001));
      expect(plausibleNutrition(day, unit: 'serving'), isTrue);
    });

    test(
      'editing a gram quantity recalculates from immutable per-100 values',
      () {
        final edited = FoodEntry(
          name: 'Cucumber',
          date: '2026-10-17',
          meal: 'Lunch',
          quantity: 200,
          unit: 'g',
          baseNutrition: trustedGramFoods['cucumber']!,
          nutritionBasis: 'per100',
        );
        expect(edited.total.kcal, 30);
        expect(edited.total.carbs, 7.2);
      },
    );
  });

  test(
    'seven-day average uses available daily values and latest same-day entry',
    () {
      final result = sevenDayWeightAverage([
        WeightEntry(date: '2026-10-10', kg: 84),
        WeightEntry(date: '2026-10-11', kg: 83),
        WeightEntry(date: '2026-10-11', kg: 82.5),
        WeightEntry(date: '2026-10-01', kg: 90),
      ], now: DateTime(2026, 10, 11));
      expect(result, closeTo(83.25, 0.0001));
    },
  );

  test('AI failures map to safe, actionable messages without raw details', () {
    final timeout = AiAssistant.failureInfo(TimeoutException('secret detail'));
    expect(timeout.code, 'timeout');
    expect(timeout.retryAllowed, isTrue);
    expect(timeout.message, contains('Check your connection'));
    final network = AiAssistant.failureInfo(
      const SocketException('private data'),
    );
    expect(network.code, 'network');
    expect(network.message, isNot(contains('private data')));
    final invalid = AiAssistant.failureInfo(
      const FormatException('raw payload'),
    );
    expect(invalid.code, 'invalid_response');
    expect(invalid.message, isNot(contains('raw payload')));
  });

  test(
    'baseline scaling follows original estimate without cumulative error',
    () {
      final entry = FoodEntry(
        id: 'rice',
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
      );
      expect(entry.total.kcal, 260);
      expect(entry.total.protein, closeTo(5.4, 1e-9));
      expect(entry.total.carbs, 56);
      expect(entry.total.fat, closeTo(.56, 1e-9));
      final returned = FoodEntry(
        id: entry.id,
        name: entry.name,
        date: entry.date,
        meal: entry.meal,
        quantity: 250,
        unit: 'g',
        originalQuantity: entry.originalQuantity,
        originalUnit: entry.originalUnit,
        nutritionBasis: 'portion',
        baseNutrition: entry.baseNutrition,
      );
      expect(returned.total.kcal, 325);
      final again = FoodEntry(
        id: entry.id,
        name: entry.name,
        date: entry.date,
        meal: entry.meal,
        quantity: 200,
        unit: 'g',
        originalQuantity: entry.originalQuantity,
        originalUnit: entry.originalUnit,
        nutritionBasis: 'portion',
        baseNutrition: entry.baseNutrition,
      );
      expect(again.total.kcal, 260);
    },
  );

  test('ratio conversion rejects invalid and incompatible quantities', () {
    expect(quantityRatio(200, 'g', 250, 'g'), .8);
    expect(quantityRatio(1, 'kg', 500, 'g'), 2);
    expect(() => quantityRatio(0, 'g', 100, 'g'), throwsArgumentError);
    expect(() => quantityRatio(1, 'cup', 100, 'g'), throwsArgumentError);
  });

  test(
    'corrupt legacy nutrition remains stored but is not usable in totals',
    () {
      final corrupt = FoodEntry(
        name: 'Unknown meal',
        date: '2026-10-17',
        meal: 'Lunch',
        quantity: 250,
        unit: 'g',
        nutritionBasis: 'serving',
        baseNutrition: const Nutrition(kcal: 82155, protein: 1000),
      );
      expect(corrupt.total.kcal, 20538750);
      expect(usableFoodEntryNutrition(corrupt), isFalse);
    },
  );

  test('structured parser supports multiple dishes and portion totals', () {
    final parsed = AiAssistant.parseAiProposal('''
      {"summary":"Two consumed dishes.","clarificationRequired":false,"items":[
        {"name":"Cooked rice","consumed_quantity":250,"unit":"g","total_kcal":325,"total_protein_g":6.75,"total_carbs_g":70,"total_fat_g":0.7,"nutrition_basis":"consumed_portion","confidence":"medium","assumptions":"Cooked white rice."},
        {"name":"Homemade dal","consumed_quantity":200,"unit":"g","total_kcal":240,"total_protein_g":14,"total_carbs_g":32,"total_fat_g":6,"nutrition_basis":"consumed_portion","confidence":"low","assumptions":"Oil amount estimated."}
      ]}
    ''');
    expect(parsed.items, hasLength(2));
    expect(parsed.items.first.totalNutrition.kcal, 325);
    expect(parsed.items.last.totalNutrition.kcal, 240);
    final entries = parsed.items
        .map(
          (item) => FoodEntry(
            name: item.name,
            date: '2026-10-17',
            meal: 'Lunch',
            quantity: item.consumedQuantity,
            unit: item.unit,
            originalQuantity: item.consumedQuantity,
            originalUnit: item.unit,
            nutritionBasis: 'portion',
            baseNutrition: item.totalNutrition,
          ),
        )
        .toList();
    final daily = entries.fold(
      const Nutrition(),
      (sum, entry) => sum + entry.total,
    );
    expect(daily.kcal, 565);
  });

  test('parser rejects missing fields, strings, malformed JSON and invalid portions', () {
    const response =
        '''{"summary":"ok","clarificationRequired":false,"items":[{"name":"Rice","consumed_quantity":250,"unit":"g","total_kcal":325,"total_protein_g":6.75,"total_carbs_g":70,"total_fat_g":0.7,"nutrition_basis":"consumed_portion","confidence":"medium","assumptions":"cooked"}]}''';
    expect(
      AiAssistant.parseAiProposal(response).items.single.consumedQuantity,
      250,
    );
    expect(
      () => AiAssistant.parseAiProposal('not json'),
      throwsFormatException,
    );
    expect(
      () => AiAssistant.parseAiProposal(response.replaceFirst('325', '"325"')),
      throwsFormatException,
    );
    expect(
      () => AiAssistant.parseAiProposal(response.replaceFirst('250', '0')),
      throwsFormatException,
    );
    expect(
      () => AiAssistant.parseAiProposal('{"items":[]}'),
      throwsFormatException,
    );
  });

  test('label basis is converted locally and retained separately', () {
    final parsed = AiAssistant.parseAiProposal('''
      {"summary":"Label states values per 100 g.","clarificationRequired":false,"items":[
        {"name":"Cereal","consumed_quantity":30,"unit":"g","total_kcal":111,"total_protein_g":3,"total_carbs_g":24,"total_fat_g":0.6,"nutrition_basis":"label_reference","confidence":"high","assumptions":"Package label clear.","label_reference":{"basis":"per_100g","quantity":100,"unit":"g","kcal":370,"protein_g":10,"carbs_g":80,"fat_g":2}}
      ]}
    ''');
    final item = parsed.items.single;
    expect(item.totalNutrition.kcal, closeTo(111, 1e-9));
    expect(item.labelReference!.quantity, 100);
    expect(item.labelReference!.nutrition.kcal, 370);
  });

  test('proposals are not persisted until user confirms', () async {
    final food = AiFoodProposal(
      name: 'Idli',
      consumedQuantity: 1,
      unit: 'piece',
      totalNutrition: const Nutrition(kcal: 58),
      confidence: 'high',
      assumptions: '',
    );
    var writes = 0;
    Future<void> persist(AiFoodProposal _) async {
      writes++;
    }

    await AiProposalCommitter.commit(
      confirmed: false,
      foods: [food],
      persist: persist,
    );
    expect(writes, 0);
    await AiProposalCommitter.commit(
      confirmed: true,
      foods: [food],
      persist: persist,
    );
    expect(writes, 1);
  });
}
