import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:calorie_tracker/data/local_database.dart';
import 'package:calorie_tracker/domain/models.dart';
import 'package:calorie_tracker/services/ai_assistant.dart';
import 'package:calorie_tracker/state/tracker_controller.dart';
import 'package:calorie_tracker/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeAiClient implements AiClient {
  int calls = 0;
  String? lastText;
  Completer<AiProposal>? pending;
  Object? nextError;

  AiProposal get proposal => AiProposal(
    items: [
      AiFoodProposal(
        name: 'Dal',
        consumedQuantity: 1,
        unit: 'bowl',
        totalNutrition: Nutrition(kcal: 210, protein: 12, carbs: 30, fat: 5),
        confidence: 'medium',
        assumptions: 'Oil amount uncertain.',
      ),
    ],
    summary: 'Estimated home cooked bowl; oil amount uncertain.',
  );

  @override
  Future<AiProposal> analyze({
    required String text,
    Uint8List? imageBytes,
    String mimeType = 'image/jpeg',
    required String workflow,
    void Function(String requestId)? onRequestId,
  }) {
    calls++;
    lastText = text;
    if (nextError case final error?) {
      nextError = null;
      return Future.error(error);
    }
    if (pending case final completer?) return completer.future;
    return Future.value(proposal);
  }

  @override
  Future<AiProposal> analyzePhoto({
    required String context,
    required String path,
    String workflow = 'food photo identification and portion estimation',
    void Function(String requestId)? onRequestId,
    int pickerPreparationMs = 0,
  }) => analyze(text: context, workflow: workflow);
}

void main() {
  late LocalDatabase testDatabase;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    const filename = 'calorie_ai_ui_test.db';
    final path = '${await databaseFactory.getDatabasesPath()}/$filename';
    await databaseFactory.deleteDatabase(path);
    testDatabase = LocalDatabase.forTesting(filename);
  });

  late TrackerController controller;
  late _FakeAiClient client;

  setUp(() async {
    controller = TrackerController(testDatabase);
    await controller.load();
    await controller.saveGoals(controller.goals.copyWith(aiEnabled: true));
    client = _FakeAiClient();
  });

  Future<void> showFood(WidgetTester tester, {bool configured = true}) async {
    await tester.pumpWidget(
      TrackerScope(
        controller: controller,
        child: MaterialApp(
          home: Scaffold(
            body: FoodScreen(aiConfigured: configured, aiClient: client),
          ),
        ),
      ),
    );
  }

  Future<void> revealAssistant(WidgetTester tester) async {
    final button = find.text('Describe a meal');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for $finder');
  }

  Future<void> pumpUntilEntry(WidgetTester tester, String name) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (controller.entries.any((entry) => entry.name == name)) return;
    }
    fail('Timed out waiting for diary entry $name');
  }

  Future<void> pumpUntilAiCalled(WidgetTester tester) async {
    for (var attempt = 0; attempt < 100 && client.calls == 0; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(client.calls, 1);
  }

  Future<void> activateDialogAction(WidgetTester tester, String label) async {
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, label),
    );
    expect(button.onPressed, isNotNull);
    button.onPressed!.call();
    await tester.pump();
  }

  Finder textFieldWithLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  testWidgets('manual amount-eaten food saves totals without calling AI', (
    tester,
  ) async {
    await showFood(tester);
    final action = find.text('Add food manually');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.enterText(
      textFieldWithLabel('Food name'),
      'Manual rice portion',
    );
    await tester.enterText(textFieldWithLabel('Amount eaten'), '200');
    await tester.enterText(textFieldWithLabel('Unit'), 'g');
    await tester.enterText(textFieldWithLabel('Calories (kcal)'), '260');
    await tester.enterText(textFieldWithLabel('Protein (g)'), '5');
    await tester.enterText(textFieldWithLabel('Carbohydrates (g)'), '56');
    await tester.enterText(textFieldWithLabel('Fat (g)'), '0.6');
    await tester.tap(find.text('Save and log food'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, textFieldWithLabel('Quantity (g)'));
    expect(find.text('Manual rice portion'), findsWidgets);
    expect(
      tester
          .widget<TextField>(textFieldWithLabel('Quantity (g)'))
          .controller!
          .text,
      '200.0',
    );
    await tester.tap(find.text('Add to diary'));
    await pumpUntilEntry(tester, 'Manual rice portion');
    final saved = controller.entries.singleWhere(
      (entry) => entry.name == 'Manual rice portion',
    );
    expect(saved.quantity, 200);
    expect(saved.total.kcal, 260);
    expect(saved.total.protein, 5);
    expect(client.calls, 0);
    expect(
      controller.foods.any((food) => food.name == 'Manual rice portion'),
      isTrue,
    );
  });

  testWidgets('manual per-100 food scales consumed quantity locally', (
    tester,
  ) async {
    await showFood(tester);
    final action = find.text('Add food manually');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.enterText(
      textFieldWithLabel('Food name'),
      'Manual rice per hundred',
    );
    await tester.tap(find.text('Nutrition for the amount I ate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nutrition per 100 g / 100 ml').last);
    await tester.pumpAndSettle();
    await tester.enterText(textFieldWithLabel('Amount consumed'), '200');
    await tester.enterText(textFieldWithLabel('Unit'), 'g');
    await tester.enterText(textFieldWithLabel('Calories (kcal)'), '130');
    await tester.enterText(textFieldWithLabel('Protein (g)'), '2.5');
    await tester.enterText(textFieldWithLabel('Carbohydrates (g)'), '28');
    await tester.enterText(textFieldWithLabel('Fat (g)'), '0.3');
    await tester.tap(find.text('Save and log food'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, textFieldWithLabel('Quantity (g)'));
    await tester.tap(find.text('Add to diary'));
    await pumpUntilEntry(tester, 'Manual rice per hundred');
    final saved = controller.entries.singleWhere(
      (entry) => entry.name == 'Manual rice per hundred',
    );
    expect(saved.total.kcal, 260);
    expect(saved.total.carbs, 56);
    expect(client.calls, 0);
    final food = controller.foods.singleWhere(
      (food) => food.name == 'Manual rice per hundred',
    );
    expect(food.nutritionBasis, 'per100');
    expect(food.referenceQuantity, 100);
  });

  testWidgets('Describe a meal opens input, shows loading and parsed result', (
    tester,
  ) async {
    final pending = Completer<AiProposal>();
    client.pending = pending;
    await showFood(tester);
    await revealAssistant(tester);
    await tester.tap(find.text('Describe a meal'));
    await tester.pumpAndSettle();
    expect(find.text('Describe your meal'), findsOneWidget);
    expect(find.byType(TextField).last, findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'one bowl of dal');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'one bowl of dal',
    );
    expect(find.text('Type or dictate a description.'), findsOneWidget);
    expect(controller.goals.aiEnabled, isTrue);
    await activateDialogAction(tester, 'Analyze');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Describe your meal'), findsNothing);
    await pumpUntil(tester, find.text('Connecting to Gemini…'));
    await pumpUntilAiCalled(tester);
    expect(client.calls, 1);
    expect(find.text('Connecting to Gemini…'), findsOneWidget);
    expect(client.calls, 1);
    expect(client.lastText, 'one bowl of dal');

    pending.complete(client.proposal);
    await pumpUntil(tester, find.text('Review estimate'));
    expect(find.text('Review estimate'), findsOneWidget);
    expect(find.textContaining('uncertain'), findsWidgets);
    expect(find.text('Confirm and save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'text and photo mock clients share the structured proposal model',
    () async {
      final textProposal = await client.analyze(
        text: 'one bowl of dal',
        workflow: 'meal description',
      );
      final photoProposal = await client.analyzePhoto(
        context: 'homemade dal, one bowl',
        path: '/mock/photo.jpg',
      );
      expect(textProposal.items.single, isA<AiFoodProposal>());
      expect(photoProposal.items.single, isA<AiFoodProposal>());
      expect(textProposal.items.single.totalNutrition.kcal, 210);
      expect(photoProposal.items.single.totalNutrition.kcal, 210);
    },
  );

  test('AI diagnostics never include exception contents', () {
    final diagnostic = AiAssistant.diagnosticForTesting(
      FormatException('private dictated meal text and secret token value'),
    );
    expect(diagnostic, contains('category:invalid_response'));
    expect(diagnostic, isNot(contains('private dictated meal text')));
    expect(diagnostic, isNot(contains('secret token value')));
  });

  testWidgets('empty meal prompt explains the required input', (tester) async {
    await showFood(tester);
    await revealAssistant(tester);
    await tester.tap(find.text('Describe a meal'));
    await tester.pumpAndSettle();
    expect(find.text('Type or dictate a description.'), findsOneWidget);
    await activateDialogAction(tester, 'Analyze');
    expect(find.text('Enter a description to analyze.'), findsOneWidget);
    expect(client.calls, 0);
  });

  testWidgets('photo and label buttons open image source choices', (
    tester,
  ) async {
    await showFood(tester);
    await revealAssistant(tester);
    await tester.tap(find.text('Photo + context'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    Navigator.of(tester.element(find.text('Take a photo'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan nutrition facts'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });

  testWidgets('AI failure explains the issue and offers retry', (tester) async {
    client.nextError = const SocketException('private network detail');
    await showFood(tester);
    await revealAssistant(tester);
    await tester.tap(find.text('Describe a meal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'two rotis');
    await activateDialogAction(tester, 'Analyze');
    await pumpUntil(tester, find.text('Connection problem'));
    expect(find.text('Connection problem'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('private network detail'), findsNothing);
    expect(find.text('two rotis'), findsAtLeastNWidgets(2));

    await tester.tap(find.text('Try again'));
    await pumpUntil(tester, find.text('Review estimate'));
    expect(client.calls, 2);
    expect(find.text('Review estimate'), findsOneWidget);
  });

  testWidgets('Review today sends real local entries after consent', (
    tester,
  ) async {
    await tester.runAsync(
      () => controller.addEntry(
        FoodEntry(
          name: 'Masala dosa',
          date: controller.selectedDate,
          meal: 'Lunch',
          quantity: 1,
          unit: 'piece',
          baseNutrition: const Nutrition(
            kcal: 310,
            protein: 8,
            carbs: 45,
            fat: 10,
          ),
          note: 'less oil',
        ),
      ),
    );
    await showFood(tester);
    await revealAssistant(tester);
    await tester.tap(find.text('Review today'));
    await tester.pumpAndSettle();
    expect(find.text('Nutrition review'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'How can I add protein?',
    );
    await activateDialogAction(tester, 'Analyze');
    await tester.pumpAndSettle();
    expect(find.text('Send this nutrition summary?'), findsOneWidget);
    expect(find.textContaining('Masala dosa'), findsWidgets);
    expect(find.textContaining('less oil'), findsWidgets);
    await tester.tap(find.text('Ask assistant'));
    await pumpUntil(tester, find.text('Nutrition review'));
    expect(client.lastText, contains('Masala dosa'));
    expect(client.lastText, contains('1.00 piece'));
    expect(client.lastText, contains('310 kcal'));
    expect(client.lastText, contains('less oil'));
  });

  testWidgets(
    'unconfigured AI gives manual fallback and does not call service',
    (tester) async {
      await showFood(tester, configured: false);
      await revealAssistant(tester);
      await tester.tap(find.text('Describe a meal'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'poha');
      await activateDialogAction(tester, 'Analyze');
      await tester.pumpAndSettle();
      expect(find.textContaining('AI is unavailable'), findsOneWidget);
      expect(find.textContaining('poha'), findsOneWidget);
      expect(client.calls, 0);
    },
  );

  testWidgets('diary is ordered below AI and above food search', (
    tester,
  ) async {
    const date = '2099-04-12';
    await tester.runAsync(() async {
      await controller.selectDate(date);
      for (final entry in [...controller.entries]) {
        await testDatabase.delete('entries', entry.id);
      }
      await controller.load();
      for (final (meal, name, kcal) in [
        ('Breakfast', 'Diary oats', 180.0),
        ('Lunch', 'Diary rice', 180.0),
        ('Dinner', 'Diary dal', 180.0),
        ('Snack', 'Diary apple', 180.0),
      ]) {
        await controller.addEntry(
          FoodEntry(
            name: name,
            date: date,
            meal: meal,
            quantity: 1,
            unit: 'serving',
            baseNutrition: Nutrition(
              kcal: kcal,
              protein: 10,
              carbs: 20,
              fat: 4,
            ),
          ),
        );
      }
    });
    await showFood(tester);
    final assistantY = tester.getTopLeft(find.text('AI food assistant')).dy;
    final diaryY = tester
        .getTopLeft(find.textContaining('Diary · Sun, 12 Apr'))
        .dy;
    final searchY = tester
        .getTopLeft(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.hintText == 'Search foods, dishes, recipes',
          ),
        )
        .dy;
    expect(assistantY, lessThan(diaryY));
    expect(diaryY, lessThan(searchY));
    for (final name in [
      'Diary oats',
      'Diary rice',
      'Diary dal',
      'Diary apple',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    for (final meal in ['Breakfast', 'Lunch', 'Dinner', 'Snack']) {
      expect(find.text(meal), findsWidgets);
    }
    expect(find.byKey(const ValueKey('food-day-totals')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('food-day-totals'))).data,
      contains('720 kcal'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('diary cards show nutrition and keep saved details collapsed', (
    tester,
  ) async {
    const date = '2099-04-14';
    final entry = FoodEntry(
      id: 'diary-card-details',
      name: 'Contextual dal',
      date: date,
      meal: 'Lunch',
      quantity: 1.5,
      unit: 'bowl',
      baseNutrition: const Nutrition(kcal: 210, protein: 12, carbs: 30, fat: 5),
      source: 'AI estimate · medium confidence',
      note: 'Less oil; tomato dal. Oil amount uncertain.',
    );
    await tester.runAsync(() async {
      await controller.selectDate(date);
      await controller.addEntry(entry);
    });
    await showFood(tester);
    expect(find.text('Contextual dal'), findsOneWidget);
    expect(find.text('1.5 bowl'), findsOneWidget);
    expect(find.text('315 kcal'), findsOneWidget);
    expect(find.text('Protein'), findsOneWidget);
    expect(find.text('18.0 g'), findsOneWidget);
    expect(find.text('45.0 g'), findsOneWidget);
    expect(find.text('7.5 g'), findsOneWidget);
    expect(
      find.text('Less oil; tomato dal. Oil amount uncertain.'),
      findsNothing,
    );
    expect(find.text('Confidence'), findsNothing);
    expect(
      find.byKey(const ValueKey('edit-food-diary-card-details')),
      findsOneWidget,
    );
    expect(client.calls, 0);

    await tester.ensureVisible(find.text('Estimation details'));
    await tester.tap(find.text('Estimation details'));
    await tester.pumpAndSettle();
    expect(find.text('AI estimate · medium confidence'), findsOneWidget);
    expect(find.text('Confidence'), findsOneWidget);
    expect(find.text('medium'), findsOneWidget);
    expect(
      find.text('Less oil; tomato dal. Oil amount uncertain.'),
      findsOneWidget,
    );
    expect(client.calls, 0);
    expect(tester.takeException(), isNull);
  });

  test(
    'seed catalogue quantities use explicit positive serving bases',
    () async {
      expect(controller.foods, isNotEmpty);
      final names = <String>{};
      for (final food in controller.foods) {
        expect(names.add(food.name.toLowerCase()), isTrue, reason: food.name);
        expect(
          food.serving.isFinite && food.serving > 0,
          isTrue,
          reason: food.name,
        );
        expect(food.unit.trim(), isNotEmpty, reason: food.name);
        final normalized = food.perHundredNutrition;
        expect(
          normalized.kcal.isFinite && normalized.kcal >= 0,
          isTrue,
          reason: food.name,
        );
        expect(
          normalized.protein.isFinite && normalized.protein >= 0,
          isTrue,
          reason: food.name,
        );
        expect(
          normalized.carbs.isFinite && normalized.carbs >= 0,
          isTrue,
          reason: food.name,
        );
        expect(
          normalized.fat.isFinite && normalized.fat >= 0,
          isTrue,
          reason: food.name,
        );
      }
      final almonds = controller.foods.singleWhere(
        (food) => food.name == 'Almonds',
      );
      expect(almonds.unit, 'g');
      expect(almonds.serving, 28);
      expect(almonds.perHundredNutrition.kcal, closeTo(164 * 100 / 28, .001));
      final rice = controller.foods.singleWhere(
        (food) => food.name == 'Cooked basmati rice',
      );
      expect(rice.unit, 'cup (158 g)');
      expect(rice.perHundredNutrition, rice.nutrition);
    },
  );

  testWidgets(
    'editing quantity preserves nutrition baseline and updates totals',
    (tester) async {
      const date = '2099-04-13';
      await tester.runAsync(() => controller.selectDate(date));
      final entry = FoodEntry(
        id: 'baseline-edit-regression',
        name: 'Editable AI rice',
        date: date,
        meal: 'Lunch',
        quantity: 1,
        unit: 'serving',
        baseNutrition: const Nutrition(
          kcal: 200,
          protein: 5,
          carbs: 40,
          fat: 2,
        ),
        source: 'AI estimate',
        originalQuantity: 2,
        originalUnit: 'serving',
      );
      await tester.runAsync(() => controller.addEntry(entry));
      await showFood(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-food-baseline-edit-regression')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('edit-food-baseline-edit-regression')),
      );
      await tester.pumpAndSettle();

      TextField fieldWithLabel(String label) => tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
      );
      expect(fieldWithLabel('Quantity (serving)').controller!.text, '1.0');
      expect(fieldWithLabel('Calories (kcal)').controller!.text, '100.0');
      expect(fieldWithLabel('Protein (g)').controller!.text, '2.5');
      expect(fieldWithLabel('Carbs (g)').controller!.text, '20.0');
      expect(fieldWithLabel('Fat (g)').controller!.text, '1.0');
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Quantity (serving)',
        ),
        '3',
      );
      await activateDialogAction(tester, 'Save changes');
      await pumpUntil(tester, find.textContaining('3.0 serving'));

      final updated = controller.entries.singleWhere((e) => e.id == entry.id);
      expect(updated.quantity, 3);
      expect(updated.total.kcal, 300);
      expect(updated.total.protein, 7.5);
      expect(controller.dayTotals.kcal, 300);

      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-food-baseline-edit-regression')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('edit-food-baseline-edit-regression')),
      );
      await tester.pumpAndSettle();
      expect(fieldWithLabel('Calories (kcal)').controller!.text, '300.0');
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Calories (kcal)',
        ),
        '330',
      );
      await activateDialogAction(tester, 'Save changes');
      await pumpUntil(tester, find.textContaining('330 kcal'));
      expect(
        controller.entries.singleWhere((e) => e.id == entry.id).total.kcal,
        330,
      );
      expect(controller.dayTotals.kcal, 330);
      final persisted = await tester.runAsync(() async {
        return (await testDatabase.byDate(
          'entries',
          date,
        )).map(FoodEntry.fromMap).singleWhere((e) => e.id == entry.id);
      });
      expect(persisted, isNotNull);
      expect(persisted!.total.kcal, 330);
      expect(client.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
