import 'dart:convert';
import 'dart:typed_data';

import 'package:calorie_tracker/services/ai_assistant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'sends schema, API key header, context and image in one request',
    () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"summary":"ok"}'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final gateway = GeminiApiModelGateway(client: client);
      final output = await gateway.generate(
        apiKey: 'private-test-key',
        model: 'gemini-3.5-flash-lite',
        systemInstruction: 'system',
        prompt: 'meal context',
        responseSchema: AiAssistant.responseSchema,
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );
      expect(output, '{"summary":"ok"}');
      expect(
        captured!.url.path,
        contains('/models/gemini-3.5-flash-lite:generateContent'),
      );
      expect(captured!.headers['x-goog-api-key'], 'private-test-key');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['systemInstruction'], isNotNull);
      expect(
        body['generationConfig']['responseSchema'],
        AiAssistant.responseSchema,
      );
      final parts = body['contents'][0]['parts'] as List;
      expect(parts.first['text'], 'meal context');
      expect(parts.last['inlineData']['mimeType'], 'image/jpeg');
      expect(parts.last['inlineData']['data'], 'AQID');
      expect(
        body['generationConfig']['thinkingConfig']['thinkingLevel'],
        'MINIMAL',
      );
    },
  );

  test('maps HTTP quota errors to sanitized useful errors', () async {
    final gateway = GeminiApiModelGateway(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Too many requests private-test-key'},
          }),
          429,
        ),
      ),
    );
    await expectLater(
      gateway.testConnection(
        apiKey: 'private-test-key',
        model: 'gemini-3.5-flash-lite',
      ),
      throwsA(
        isA<GeminiApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having(
              (e) => e.message,
              'sanitized message',
              isNot(contains('private-test-key')),
            ),
      ),
    );
  });
}
