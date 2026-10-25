import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/nutrition_validation.dart';

class AiProposal {
  const AiProposal({
    required this.items,
    required this.summary,
    this.clarificationRequired = false,
  });
  final List<AiFoodProposal> items;
  final String summary;
  final bool clarificationRequired;
}

class NutritionReference {
  const NutritionReference({
    required this.quantity,
    required this.unit,
    required this.nutrition,
    required this.basis,
  });
  final double quantity;
  final String unit;
  final Nutrition nutrition;
  final String basis;
}

class AiFoodProposal {
  const AiFoodProposal({
    required this.name,
    required this.consumedQuantity,
    required this.unit,
    required this.totalNutrition,
    required this.confidence,
    required this.assumptions,
    this.labelReference,
  });
  final String name;
  final double consumedQuantity;
  final String unit;
  final Nutrition totalNutrition;
  final String confidence;
  final String assumptions;
  final NutritionReference? labelReference;
}

abstract interface class AiClient {
  Future<AiProposal> analyze({
    required String text,
    Uint8List? imageBytes,
    String mimeType = 'image/jpeg',
    required String workflow,
    void Function(String requestId)? onRequestId,
  });

  Future<AiProposal> analyzePhoto({
    required String context,
    required String path,
    String workflow = 'food photo identification and portion estimation',
    void Function(String requestId)? onRequestId,
    int pickerPreparationMs = 0,
  });
}

class AiFailureInfo {
  const AiFailureInfo({
    required this.title,
    required this.message,
    required this.retryAllowed,
    required this.code,
  });

  final String title;
  final String message;
  final bool retryAllowed;
  final String code;
}

class AiProposalCommitter {
  static Future<void> commit({
    required bool confirmed,
    required List<AiFoodProposal> foods,
    required Future<void> Function(AiFoodProposal food) persist,
  }) async {
    if (!confirmed) return;
    for (final food in foods) {
      await persist(food);
    }
  }
}

abstract interface class AiModelGateway {
  Future<String?> generate({
    required String apiKey,
    required String model,
    required String systemInstruction,
    required String prompt,
    required Map<String, Object?> responseSchema,
    Uint8List? imageBytes,
    required String mimeType,
  });

  Future<void> testConnection({required String apiKey, required String model});
}

abstract interface class AiCredentialStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAiCredentialStorage implements AiCredentialStorage {
  SecureAiCredentialStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryAiCredentialStorage implements AiCredentialStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class GeminiApiException implements Exception {
  const GeminiApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'GeminiApiException($statusCode)';
}

class GeminiApiModelGateway implements AiModelGateway {
  GeminiApiModelGateway({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  Uri _uri(String model) => Uri.https(
    'generativelanguage.googleapis.com',
    '/v1beta/models/$model:generateContent',
  );

  Future<Map<String, Object?>> _post({
    required String apiKey,
    required String model,
    required Map<String, Object?> body,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw StateError('Add your Gemini API key in AI Setup.');
    }
    final response = await _client
        .post(
          _uri(model),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey.trim(),
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 75));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Gemini returned an invalid response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final message = error is Map ? error['message']?.toString() : null;
      throw GeminiApiException(
        response.statusCode,
        _safeApiMessage(response.statusCode, message, apiKey),
      );
    }
    return decoded;
  }

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
    final parts = <Map<String, Object?>>[
      {'text': prompt},
      if (imageBytes != null)
        {
          'inlineData': {
            'mimeType': mimeType,
            'data': base64Encode(imageBytes),
          },
        },
    ];
    final result = await _post(
      apiKey: apiKey,
      model: model,
      body: {
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
        'contents': [
          {'role': 'user', 'parts': parts},
        ],
        'generationConfig': {
          'maxOutputTokens': AiAssistant.maxOutputTokens,
          'responseMimeType': 'application/json',
          'responseSchema': responseSchema,
          'thinkingConfig': {'thinkingLevel': 'MINIMAL'},
        },
      },
    );
    final candidates = result['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      return null;
    }
    final content = (candidates.first as Map)['content'];
    if (content is! Map || content['parts'] is! List) return null;
    return (content['parts'] as List)
        .whereType<Map>()
        .map((part) => part['text'])
        .whereType<String>()
        .join();
  }

  @override
  Future<void> testConnection({
    required String apiKey,
    required String model,
  }) async {
    final result = await _post(
      apiKey: apiKey,
      model: model,
      body: {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': 'Reply with OK.'},
            ],
          },
        ],
        'generationConfig': {'maxOutputTokens': 8},
      },
    );
    if (result['candidates'] is! List ||
        (result['candidates'] as List).isEmpty) {
      throw const FormatException('Gemini returned no test response.');
    }
  }

  static String _safeApiMessage(int status, String? message, String apiKey) {
    final hint = switch (status) {
      400 => 'Request rejected. Check the selected model and request format.',
      401 || 403 =>
        'API key or Gemini API access was rejected. Check your AI Studio key.',
      404 => 'The selected model is not available for this API key.',
      429 => 'Your Google AI Studio quota or rate limit was reached.',
      >= 500 => 'Gemini is temporarily unavailable. Retry later.',
      _ => 'Gemini request failed.',
    };
    final detail = (message ?? '')
        .replaceAll(apiKey, '[redacted]')
        .replaceAll(RegExp(r'AIza[0-9A-Za-z_-]{20,}'), '[redacted]')
        .replaceAll(RegExp(r'[\r\n]+'), ' ');
    return detail.isEmpty ? hint : '$hint $detail';
  }
}

class AiAssistant implements AiClient {
  AiAssistant._()
    : _gateway = GeminiApiModelGateway(),
      _storage = SecureAiCredentialStorage();

  @visibleForTesting
  AiAssistant.forTesting({
    required AiModelGateway gateway,
    AiCredentialStorage? storage,
  }) : _storage = storage ?? MemoryAiCredentialStorage() {
    _gateway = gateway;
    _apiKey = 'test-api-key';
  }

  static final instance = AiAssistant._();
  late final AiModelGateway _gateway;
  final AiCredentialStorage _storage;
  static const _apiKeyStorage = 'gemini_api_key';
  static const _modelStorage = 'gemini_model';
  String? _apiKey;
  String _modelName = defaultModelName;
  bool get configured => _apiKey?.isNotEmpty ?? false;
  String get modelName => _modelName;
  static const defaultModelName = 'gemini-3.5-flash-lite';
  static const availableModels = [defaultModelName, 'gemini-3.8-flash'];
  static const _thinkingLevelName = 'MINIMAL';
  static const maxOutputTokens = 1024;
  static int _requestSequence = 0;

  Future<bool> loadKeyState() async {
    _apiKey = await _storage.read(_apiKeyStorage);
    _modelName = await _storage.read(_modelStorage) ?? defaultModelName;
    return configured;
  }

  Future<void> saveApiKey(String value) async {
    final key = value.trim();
    if (key.isEmpty) throw ArgumentError('Paste an API key first.');
    await _storage.write(_apiKeyStorage, key);
    _apiKey = key;
  }

  Future<void> removeApiKey() async {
    await _storage.delete(_apiKeyStorage);
    _apiKey = null;
  }

  Future<void> setModel(String model) async {
    if (!availableModels.contains(model)) {
      throw ArgumentError('Unsupported model.');
    }
    _modelName = model;
    await _storage.write(_modelStorage, model);
  }

  Future<void> testConnection() async {
    final key = _apiKey ?? await _storage.read(_apiKeyStorage);
    if (key == null || key.isEmpty) {
      throw StateError('Add your Gemini API key in AI Setup.');
    }
    final watch = Stopwatch()..start();
    final requestId = 'test-${_newRequestId()}';
    _perf(requestId, 'connection test', 'request_start', watch, {
      'model': modelName,
      'provider': 'gemini_api',
    });
    try {
      _perf(requestId, 'connection test', 'gemini_send', watch, {
        'model': modelName,
        'provider': 'gemini_api',
      });
      await _gateway
          .testConnection(apiKey: key, model: _modelName)
          .timeout(const Duration(seconds: 45));
      _perf(requestId, 'connection test', 'request_success', watch, {
        'provider': 'gemini_api',
      });
    } catch (error) {
      _perf(requestId, 'connection test', 'request_failure', watch, {
        'error': _safeDiagnostic(error),
      });
      rethrow;
    }
  }

  static String _newRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(++_requestSequence).toRadixString(36)}';

  static String _workflowName(String workflow) => switch (workflow) {
    'connection test' => 'connection_test',
    'nutrition review' => 'daily_review',
    'nutrition label extraction' => 'nutrition_label',
    'food photo' ||
    'food photo identification and portion estimation' => 'photo_analysis',
    _ => 'text_meal_analysis',
  };

  static void _perf(
    String requestId,
    String workflow,
    String event,
    Stopwatch watch, [
    Map<String, Object?> fields = const {},
  ]) {
    if (!kDebugMode) return;
    final values = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrint(
      '[AI_PERF] id=$requestId workflow=${_workflowName(workflow)} timestamp=${DateTime.now().toUtc().toIso8601String()} event=$event elapsed_ms=${watch.elapsedMilliseconds}${values.isEmpty ? '' : ' $values'}',
    );
  }

  static void logUiStage({
    required String requestId,
    required String workflow,
    required String event,
    required int elapsedMs,
    Map<String, Object?> fields = const {},
  }) {
    if (!kDebugMode) return;
    final values = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrint(
      '[AI_PERF] id=$requestId workflow=${_workflowName(workflow)} timestamp=${DateTime.now().toUtc().toIso8601String()} event=$event elapsed_ms=$elapsedMs${values.isEmpty ? '' : ' $values'}',
    );
  }

  static const Map<String, Object?> responseSchema = {
    'type': 'OBJECT',
    'properties': {
      'summary': {'type': 'STRING'},
      'clarificationRequired': {'type': 'BOOLEAN'},
      'items': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'name': {'type': 'STRING'},
            'consumed_quantity': {
              'type': 'NUMBER',
              'minimum': 0.000001,
              'maximum': 5000,
            },
            'unit': {'type': 'STRING'},
            'total_kcal': {'type': 'NUMBER', 'minimum': 0, 'maximum': 2500},
            'total_protein_g': {'type': 'NUMBER', 'minimum': 0, 'maximum': 300},
            'total_carbs_g': {'type': 'NUMBER', 'minimum': 0, 'maximum': 300},
            'total_fat_g': {'type': 'NUMBER', 'minimum': 0, 'maximum': 300},
            'nutrition_basis': {
              'type': 'STRING',
              'enum': ['consumed_portion', 'label_reference'],
            },
            'confidence': {
              'type': 'STRING',
              'enum': ['low', 'medium', 'high'],
            },
            'assumptions': {'type': 'STRING'},
            'label_reference': {
              'type': 'OBJECT',
              'properties': {
                'basis': {
                  'type': 'STRING',
                  'enum': ['per_100g', 'per_100ml', 'per_serving'],
                },
                'quantity': {
                  'type': 'NUMBER',
                  'minimum': 0.000001,
                  'maximum': 5000,
                },
                'unit': {'type': 'STRING'},
                'kcal': {'type': 'NUMBER', 'minimum': 0, 'maximum': 2500},
                'protein_g': {'type': 'NUMBER', 'minimum': 0, 'maximum': 300},
                'carbs_g': {'type': 'NUMBER', 'minimum': 0, 'maximum': 300},
                'fat_g': {'type': 'NUMBER', 'minimum': 0, 'maximum': 300},
              },
              'required': [
                'basis',
                'quantity',
                'unit',
                'kcal',
                'protein_g',
                'carbs_g',
                'fat_g',
              ],
            },
          },
          'required': [
            'name',
            'consumed_quantity',
            'unit',
            'total_kcal',
            'total_protein_g',
            'total_carbs_g',
            'total_fat_g',
            'nutrition_basis',
            'confidence',
            'assumptions',
          ],
        },
      },
    },
    'required': ['summary', 'clarificationRequired', 'items'],
  };

  static AiFailureInfo failureInfo(Object error) {
    if (error is TimeoutException) {
      return const AiFailureInfo(
        title: 'Analysis took too long',
        message: 'The request did not finish in time. Check your connection and retry, or continue with manual logging.',
        retryAllowed: true,
        code: 'timeout',
      );
    }
    if (error is GeminiApiException) {
      final quota = error.statusCode == 429;
      final server = error.statusCode >= 500;
      return AiFailureInfo(
        title: quota
            ? 'Gemini quota reached'
            : server
            ? 'Gemini is temporarily unavailable'
            : 'Gemini request failed',
        message:
            '${error.message} No food was saved. Retry or use manual logging.',
        retryAllowed: server || error.statusCode == 429,
        code: quota
            ? 'quota'
            : server
            ? 'service_unavailable'
            : 'gemini_api_error',
      );
    }
    final detail = error.toString().toLowerCase();
    if (error is SocketException ||
        error is HandshakeException ||
        detail.contains('network') ||
        detail.contains('socket')) {
      return const AiFailureInfo(
        title: 'Connection problem',
        message: 'Connect to the internet and retry. You can continue with manual logging while offline.',
        retryAllowed: true,
        code: 'network',
      );
    }
    if (error is FormatException) {
      return const AiFailureInfo(
        title: 'Could not read the AI response',
        message: 'No food was saved. Retry once, or use search and custom food entry instead.',
        retryAllowed: true,
        code: 'invalid_response',
      );
    }
    if (error is StateError) {
      return const AiFailureInfo(
        title: 'API key required',
        message: 'Add your Gemini API key in Settings → AI Setup.',
        retryAllowed: false,
        code: 'not_configured',
      );
    }
    return const AiFailureInfo(
      title: 'Analysis failed',
      message: 'No food was saved. Check your connection and Gemini API key, then retry or continue with manual logging.',
      retryAllowed: true,
      code: 'unknown',
    );
  }

  @override
  Future<AiProposal> analyze({
    required String text,
    Uint8List? imageBytes,
    String mimeType = 'image/jpeg',
    required String workflow,
    void Function(String requestId)? onRequestId,
  }) async {
    final watch = Stopwatch()..start();
    final requestId = _newRequestId();
    onRequestId?.call(requestId);
    return _runRequest(
      requestId: requestId,
      watch: watch,
      text: text,
      imageBytes: imageBytes,
      mimeType: mimeType,
      workflow: workflow,
      preparationMs: 0,
    );
  }

  static const _systemInstruction =
      'Estimate nutrition for the food diary. Return only concise JSON matching the schema. Include each consumed dish once, not its ingredients. Distinguish recipe amounts and batch yield from the amount eaten; never assume the whole batch was eaten. If the amount eaten is unclear, set clarificationRequired and name the missing detail. Nutrition is the total for consumed_quantity in kcal and grams. For label scans, include readable printed values and basis; the app scales them locally. Keep summary and assumptions brief, state uncertainty, avoid false precision, and do not give medical advice or chain-of-thought.';

  Future<AiProposal> _runRequest({
    required String requestId,
    required Stopwatch watch,
    required String text,
    required Uint8List? imageBytes,
    required String mimeType,
    required String workflow,
    required int preparationMs,
  }) async {
    final apiKey = _apiKey ?? await _storage.read(_apiKeyStorage);
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('Add your Gemini API key in AI Setup.');
    }
    _perf(requestId, workflow, 'request_start', watch, {
      'model': modelName,
      'thinking_level': _thinkingLevelName,
      'max_output_tokens': maxOutputTokens,
      'provider': 'gemini_api',
      'image_attached': imageBytes != null,
      if (imageBytes != null) 'image_bytes': imageBytes.length,
      'text_length': text.length,
      'preparation_ms': preparationMs,
    });
    final modelWatch = Stopwatch()..start();
    _perf(requestId, workflow, 'model_setup_success', watch, {
      'setup_ms': modelWatch.elapsedMilliseconds,
      'client_reused': true,
      'model': modelName,
      'thinking_level': _thinkingLevelName,
      'max_output_tokens': maxOutputTokens,
      'provider': 'gemini_api',
    });

    final preparationWatch = Stopwatch()..start();
    final objective = workflow == 'nutrition label extraction'
        ? 'Extract readable label values and basis. Return totals for the amount eaten. If that amount is unknown or values are unreadable, request clarification; do not guess.'
        : workflow == 'nutrition review'
        ? 'Briefly answer using only supplied food entries, totals, and targets. Any suggestions are optional, never logged. Do not give medical advice.'
        : 'Identify consumed dishes and amount eaten. Return nutrition totals for each eaten portion; keep uncertainty brief and do not create ingredient rows.';
    final prompt =
        'Task: $objective Input: ${text.trim().isEmpty ? 'No text; inspect the attached food image.' : text.trim()}';
    _perf(requestId, workflow, 'payload_prepared', watch, {
      'stage_ms': preparationWatch.elapsedMilliseconds,
      'image_attached': imageBytes != null,
      if (imageBytes != null) 'image_bytes': imageBytes.length,
      'text_length': text.length,
    });
    try {
      final requestWatch = Stopwatch()..start();
      _perf(requestId, workflow, 'gemini_send', watch, {
        'model': modelName,
        'provider': 'gemini_api',
        'thinking_level': _thinkingLevelName,
        'image_attached': imageBytes != null,
        if (imageBytes != null) 'image_bytes': imageBytes.length,
        'text_length': text.length,
      });
      final raw = await _gateway
          .generate(
            apiKey: apiKey,
            model: _modelName,
            systemInstruction: _systemInstruction,
            prompt: prompt,
            responseSchema: responseSchema,
            imageBytes: imageBytes,
            mimeType: mimeType,
          )
          .timeout(const Duration(seconds: 75));
      final requestMs = requestWatch.elapsedMilliseconds;
      _perf(requestId, workflow, 'gemini_response_received', watch, {
        'model': modelName,
        'client_request_ms': requestMs,
        'server_inference_ms': 'unavailable',
      });
      if (raw == null || raw.isEmpty) {
        throw const FormatException('The assistant returned no proposal.');
      }
      final jsonWatch = Stopwatch()..start();
      late final Object? decoded;
      try {
        decoded = jsonDecode(raw);
        _perf(requestId, workflow, 'json_parse_success', watch, {
          'stage_ms': jsonWatch.elapsedMilliseconds,
        });
      } catch (error) {
        _perf(requestId, workflow, 'json_parse_failure', watch, {
          'stage_ms': jsonWatch.elapsedMilliseconds,
          'error': _safeDiagnostic(error),
        });
        rethrow;
      }
      final validationWatch = Stopwatch()..start();
      late final AiProposal proposal;
      try {
        proposal = _parseDecodedProposal(
          decoded,
          allowEmpty: workflow == 'nutrition review',
        );
        _perf(requestId, workflow, 'validation_success', watch, {
          'stage_ms': validationWatch.elapsedMilliseconds,
          'items': proposal.items.length,
        });
      } catch (error) {
        _perf(requestId, workflow, 'validation_failure', watch, {
          'stage_ms': validationWatch.elapsedMilliseconds,
          'error': _safeDiagnostic(error),
        });
        rethrow;
      }
      _perf(requestId, workflow, 'request_success', watch, {
        'items': proposal.items.length,
        'parse_validation_success': true,
      });
      return proposal;
    } catch (error) {
      _perf(requestId, workflow, 'request_failure', watch, {
        'error': _safeDiagnostic(error),
      });
      rethrow;
    }
  }

  static String _safeDiagnostic(Object error) {
    return 'type:${error.runtimeType};category:${failureInfo(error).code}';
  }

  @visibleForTesting
  static String diagnosticForTesting(Object error) => _safeDiagnostic(error);

  static AiProposal parseAiProposal(String raw, {bool allowEmpty = false}) {
    final decoded = jsonDecode(raw);
    return _parseDecodedProposal(decoded, allowEmpty: allowEmpty);
  }

  static AiProposal _parseDecodedProposal(
    Object? decoded, {
    required bool allowEmpty,
  }) {
    if (decoded is! Map<String, dynamic> ||
        decoded['items'] is! List ||
        decoded['summary'] is! String ||
        decoded['clarificationRequired'] is! bool) {
      throw const FormatException('Invalid assistant response.');
    }
    final items = (decoded['items'] as List).map((value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid food item in AI response.');
      }
      return _parseProposalItem(value);
    }).toList();
    final clarificationRequired = decoded['clarificationRequired'] as bool;
    if (items.isEmpty && !allowEmpty && !clarificationRequired) {
      throw const FormatException(
        'No valid food estimates were returned. Add the food manually.',
      );
    }
    return AiProposal(
      items: items,
      summary: decoded['summary'] as String,
      clarificationRequired: clarificationRequired,
    );
  }

  static AiFoodProposal _parseProposalItem(Map<String, dynamic> item) {
    final name = item['name'];
    final quantity = _finite(item['consumed_quantity']);
    final unit = item['unit'];
    final kcal = _finite(item['total_kcal']);
    final protein = _finite(item['total_protein_g']);
    final carbs = _finite(item['total_carbs_g']);
    final fat = _finite(item['total_fat_g']);
    final confidence = item['confidence'];
    final assumptions = item['assumptions'];
    if (name is! String ||
        name.trim().isEmpty ||
        quantity == null ||
        quantity <= 0 ||
        unit is! String ||
        unit.trim().isEmpty ||
        [
          kcal,
          protein,
          carbs,
          fat,
        ].any((value) => value == null || value < 0) ||
        !const ['low', 'medium', 'high'].contains(confidence) ||
        assumptions is! String ||
        item['nutrition_basis'] is! String) {
      throw const FormatException('AI response is missing valid food values.');
    }
    final returned = Nutrition(
      kcal: kcal!,
      protein: protein!,
      carbs: carbs!,
      fat: fat!,
    );
    final reference = item['label_reference'] == null
        ? null
        : _parseLabelReference(item['label_reference']);
    final basis = item['nutrition_basis'] as String;
    if (basis == 'label_reference') {
      if (reference == null) {
        throw const FormatException(
          'AI label values are missing their reference basis.',
        );
      }
      final normalized = _scaleReference(reference, quantity, unit.trim());
      if (!plausibleNutrition(reference.nutrition, unit: reference.unit) ||
          !plausibleNutrition(normalized, unit: 'serving')) {
        throw const FormatException('AI label nutrition failed validation.');
      }
      return AiFoodProposal(
        name: name.trim(),
        consumedQuantity: quantity,
        unit: unit.trim(),
        totalNutrition: normalized,
        confidence: confidence as String,
        assumptions: assumptions,
        labelReference: reference,
      );
    }
    if (basis != 'consumed_portion' ||
        reference != null ||
        !plausibleNutrition(returned, unit: 'serving')) {
      throw const FormatException('AI portion nutrition failed validation.');
    }
    return AiFoodProposal(
      name: name.trim(),
      consumedQuantity: quantity,
      unit: unit.trim(),
      totalNutrition: returned,
      confidence: confidence as String,
      assumptions: assumptions,
    );
  }

  static NutritionReference _parseLabelReference(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid nutrition label reference.');
    }
    final quantity = _finite(value['quantity']);
    final unit = value['unit'];
    final basis = value['basis'];
    final kcal = _finite(value['kcal']);
    final protein = _finite(value['protein_g']);
    final carbs = _finite(value['carbs_g']);
    final fat = _finite(value['fat_g']);
    if (quantity == null ||
        quantity <= 0 ||
        unit is! String ||
        unit.trim().isEmpty ||
        !const ['per_100g', 'per_100ml', 'per_serving'].contains(basis) ||
        [
          kcal,
          protein,
          carbs,
          fat,
        ].any((number) => number == null || number < 0)) {
      throw const FormatException('Nutrition label reference is incomplete.');
    }
    if ((basis == 'per_100g' &&
            (quantity != 100 || unit.toLowerCase() != 'g')) ||
        (basis == 'per_100ml' &&
            (quantity != 100 || unit.toLowerCase() != 'ml'))) {
      throw const FormatException(
        'Nutrition label basis conflicts with its units.',
      );
    }
    return NutritionReference(
      quantity: quantity,
      unit: unit.trim(),
      nutrition: Nutrition(
        kcal: kcal!,
        protein: protein!,
        carbs: carbs!,
        fat: fat!,
      ),
      basis: basis as String,
    );
  }

  static Nutrition _scaleReference(
    NutritionReference reference,
    double quantity,
    String unit,
  ) => reference.nutrition.scale(
    quantityRatio(quantity, unit, reference.quantity, reference.unit),
  );

  static double? _finite(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }

  @override
  Future<AiProposal> analyzePhoto({
    required String context,
    required String path,
    String workflow = 'food photo identification and portion estimation',
    void Function(String requestId)? onRequestId,
    int pickerPreparationMs = 0,
  }) async {
    final watch = Stopwatch()..start();
    final requestId = _newRequestId();
    onRequestId?.call(requestId);
    _perf(requestId, workflow, 'request_start', watch, {
      'model': modelName,
      'thinking_level': _thinkingLevelName,
      'max_output_tokens': maxOutputTokens,
      'provider': 'gemini_api',
      'image_attached': true,
      'image_bytes': 'pending',
      'text_length': context.length,
      'picker_preparation_ms': pickerPreparationMs,
    });
    final file = File(path);
    late final Uint8List bytes;
    final imageWatch = Stopwatch()..start();
    try {
      bytes = await file.readAsBytes();
      _perf(requestId, workflow, 'image_load_success', watch, {
        'stage_ms': imageWatch.elapsedMilliseconds,
        'image_bytes': bytes.length,
        'picker_preparation_ms': pickerPreparationMs,
      });
    } catch (error) {
      _perf(requestId, workflow, 'image_load_failure', watch, {
        'stage_ms': imageWatch.elapsedMilliseconds,
        'error': _safeDiagnostic(error),
      });
      _perf(requestId, workflow, 'request_failure', watch, {
        'error': 'image_load_failure',
      });
      rethrow;
    }
    final lowerPath = path.toLowerCase();
    final mimeType = lowerPath.endsWith('.png')
        ? 'image/png'
        : lowerPath.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    return _runRequest(
      requestId: requestId,
      watch: watch,
      text: context,
      imageBytes: bytes,
      mimeType: mimeType,
      workflow: workflow,
      preparationMs: pickerPreparationMs + imageWatch.elapsedMilliseconds,
    );
  }
}
