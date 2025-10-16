// =========================================
// UPDATED: lib/editor/plugins/llm_editor/providers/llm_provider.dart
// =========================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';

abstract class LlmProvider {
  String get id;
  String get name;
  List<String> get availableModels;

  Stream<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId,
  });
}

class DummyProvider implements LlmProvider {
  @override
  String get id => 'dummy';
  @override
  String get name => 'Dummy (Testing)';
  @override
  List<String> get availableModels => ['dummy-model'];

  @override
  Stream<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId,
  }) async* { // Using an async generator
    final response = "This is a streaming dummy response for model **'$modelId'** to your prompt: **'$prompt'**. Here is some markdown code:\n\n```dart\nvoid main() {\n  print('Hello, Streaming World!');\n}\n```\n\nLists are also supported:\n* Item 1\n* Item 2";
    final words = response.split(' ');
    for (final word in words) {
      await Future.delayed(const Duration(milliseconds: 50));
      yield '$word ';
    }
  }
}

// A concrete implementation for Google's Gemini API.
class GeminiProvider implements LlmProvider {
  @override
  String get id => 'gemini';
  @override
  String get name => 'Google Gemini';
  @override
  // UPDATED: Use the newer model names from the documentation.
  List<String> get availableModels => [
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
      ];

  final String _apiKey;
  GeminiProvider(this._apiKey);

  @override
  Stream<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId,
  }) async* {
    if (_apiKey.isEmpty) {
      yield 'Error: Google Gemini API key is not set in the plugin settings.';
      return;
    }

    final client = http.Client();
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$modelId:streamGenerateContent?alt=sse');
    
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    final contents = [
      ...history.map((m) => {
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': [{'text': m.content}]
      }),
      {
        'role': 'user',
        'parts': [{'text': prompt}]
      }
    ];
    final body = jsonEncode({'contents': contents});

    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = body;

      final response = await client.send(request);

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n').where((line) => line.isNotEmpty);
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            final json = jsonDecode(data);
            final content = json['candidates']?[0]?['content']?['parts']?[0]?['text'];
            if (content != null) {
              yield content as String;
            }
          }
        }
      }
    } catch (e) {
      yield 'Network Error: Failed to connect to Google Gemini API. $e';
    } finally {
      client.close();
    }
  }
}