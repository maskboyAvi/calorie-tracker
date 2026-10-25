import 'dart:convert';
import 'dart:typed_data';

import 'package:calorie_tracker/services/ai_assistant.dart';
import 'package:calorie_tracker/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApiGateway implements AiModelGateway {
  String? response = jsonEncode({
    'summary': 'One bowl estimate.',
    'clarificationRequired': false,
    'items': [
      {
        'name': 'Dal',
        'consumed_quantity': 1,
        'unit': 'bowl',
        'total_kcal': 200,
        'total_protein_g': 10,
        'total_carbs_g': 25,
        'total_fat_g': 5,
        'nutrition_basis': 'consumed_portion',
        'confidence': 'medium',
        'assumptions': 'One medium bowl.',
      },
    ],
  });
  int generateCalls = 0;
  int testCalls = 0;
  String? systemInstruction;
  String? prompt;
  Uint8List? imageBytes;
  String? mimeType;
  Map<String, Object?>? schema;

  @override
  Future<String?> generate({
    required String apiKey,
    required String model,
    required String systemInstruction,
    required String prompt,
    required Map<String, Object?> responseSchema,
    Uint8List? imageBytes,
    required String mimeType,
  }) async {
    generateCalls++;
    this.systemInstruction = systemInstruction;
    this.prompt = prompt;
    this.imageBytes = imageBytes;
    this.mimeType = mimeType;
    schema = responseSchema;
    return response;
  }

  @override
  Future<void> testConnection({
    required String apiKey,
    required String model,
  }) async {
    testCalls++;
  }
}

void main() {
  test('key and model persist and key can be removed', () async {
    final storage = MemoryAiCredentialStorage();
    final assistant = AiAssistant.forTesting(
      gateway: _FakeApiGateway(),
      storage: storage,
    );
    await assistant.saveApiKey('AIza-example-private-key');
    await assistant.setModel('gemini-3.8-flash');
    expect(await assistant.loadKeyState(), isTrue);
    expect(assistant.modelName, 'gemini-3.8-flash');
    await assistant.removeApiKey();
    expect(await assistant.loadKeyState(), isFalse);
    expect(storage.values.values, isNot(contains('AIza-example-private-key')));
  });

  test('Gemini gateway receives text and parses structured result', () async {
    final gateway = _FakeApiGateway();
    final assistant = AiAssistant.forTesting(gateway: gateway);

    final proposal = await assistant.analyze(
      text: '200 g dal',
      workflow: 'food text analysis',
    );

    expect(gateway.generateCalls, 1);
    expect(gateway.systemInstruction, contains('Estimate nutrition'));
    expect(gateway.prompt, contains('200 g dal'));
    expect(gateway.schema, AiAssistant.responseSchema);
    expect(proposal.items.single.name, 'Dal');
    expect(proposal.items.single.totalNutrition.kcal, 200);
  });

  test(
    'photo context and image are passed together to one model call',
    () async {
      final gateway = _FakeApiGateway();
      final assistant = AiAssistant.forTesting(gateway: gateway);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      await assistant.analyze(
        text: 'low-oil lunch',
        imageBytes: bytes,
        mimeType: 'image/jpeg',
        workflow: 'food photo',
      );

      expect(gateway.generateCalls, 1);
      expect(gateway.prompt, contains('low-oil lunch'));
      expect(gateway.imageBytes, bytes);
      expect(gateway.mimeType, 'image/jpeg');
    },
  );

  test('test connection makes one explicit Gemini call', () async {
    final gateway = _FakeApiGateway();
    final assistant = AiAssistant.forTesting(gateway: gateway);

    await assistant.testConnection();

    expect(gateway.testCalls, 1);
    expect(gateway.generateCalls, 0);
  });

  testWidgets('AI setup contains key setup without debug token controls', (
    tester,
  ) async {
    final gateway = _FakeApiGateway();
    final assistant = AiAssistant.forTesting(gateway: gateway);
    await tester.pumpWidget(
      MaterialApp(home: AiSetupScreen(assistant: assistant)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gemini_api_key_input')), findsOneWidget);
    expect(find.byKey(const Key('gemini_model_selector')), findsOneWidget);
    expect(find.text('Get an API key in Google AI Studio'), findsOneWidget);
    expect(find.text('App Check debug token'), findsNothing);
    expect(find.text('Copy token'), findsNothing);
  });
}
