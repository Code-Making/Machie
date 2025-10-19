// =========================================
// UPDATED: lib/editor/plugins/llm_editor/providers/llm_provider.dart
// =========================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_types.dart'; // ADDED

abstract class LlmProvider {
  String get id;
  String get name;
  List<String> get availableModels;

  // MODIFIED: Return type changed
  Stream<LlmResponseEvent> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId,
  });

  // ADDED: New method for counting tokens
  Future<int> countTokens({
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

  // ADDED: Dummy implementation for countTokens
  @override
  Future<int> countTokens({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId,
  }) async {
    // Simple approximation for the dummy provider
    return (prompt.length / 4).ceil();
  }
  
  // MODIFIED: Dummy implementation for the new stream type
  @override
  Stream<LlmResponseEvent> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId,
  }) async* {
    final response = "This is a streaming dummy response for model **'$modelId'** to your prompt: **'$prompt'**. Here is some markdown code:\n\n```dart\nvoid main() {\n  print('Hello, Streaming World!');\n}\n```\n\nLists are also supported:\n* Item 1\n* Item 2";
    final words = response.split(' ');
    for (final word in words) {
      await Future.delayed(const Duration(milliseconds: 5));
      yield LlmTextChunk('$word ');
    }
    // Yield dummy metadata at the end
    yield LlmResponseMetadata(
      promptTokenCount: (prompt.length / 4).ceil(),
      responseTokenCount: (response.length / 4).ceil(),
    );
  }
}

// A concrete implementation for Google's Gemini API.
class GeminiProvider implements LlmProvider {
  // ... (id, name, availableModels, constructor are unchanged)
  @override
  String get id => 'gemini';
  @override
  String get name => 'Google Gemini';
  @override
  List<String> get availableModels => [
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
      ];
      
  final String _apiKey;
  GeminiProvider(this._apiKey);

  // ADDED: Full implementation for countTokens
  @override
  Future<int> countTokens({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId,
  }) async {
    if (_apiKey.isEmpty) return 0;

    final client = http.Client();
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$modelId:countTokens');

    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    final contents = _buildContents(history, prompt);
    final body = jsonEncode({'contents': contents});

    try {
      final response = await client.post(uri, headers: headers, body: body);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['totalTokens'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      return 0; // Silently fail on count error
    } finally {
      client.close();
    }
  }

  // MODIFIED: Full implementation for the new stream type
  @override
  Stream<LlmResponseEvent> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId,
  }) async* {
    if (_apiKey.isEmpty) {
      yield LlmError('Error: Google Gemini API key is not set in the plugin settings.');
      return;
    }

    final client = http.Client();
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$modelId:streamGenerateContent?alt=sse');

    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    final contents = _buildContents(history, prompt);
    final body = jsonEncode({'contents': contents});

    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = body;

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        yield LlmError('API Error (${response.statusCode}): $errorBody');
        return;
      }

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n').where((line) => line.isNotEmpty);
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            final json = jsonDecode(data);

            // Yield text chunk if available
            final textContent = json['candidates']?[0]?['content']?['parts']?[0]?['text'];
            if (textContent != null) {
              yield LlmTextChunk(textContent as String);
            }
            
            // Yield metadata if available (usually in the last chunk)
            final usageMetadata = json['usageMetadata'];
            if (usageMetadata != null) {
              yield LlmResponseMetadata(
                promptTokenCount: usageMetadata['promptTokenCount'] as int? ?? 0,
                responseTokenCount: usageMetadata['candidatesTokenCount'] as int? ?? 0,
              );
            }

            // Handle blocked prompts
            final promptFeedback = json['promptFeedback'];
            if (promptFeedback != null && promptFeedback['blockReason'] != null) {
                yield LlmError('Prompt blocked due to: ${promptFeedback['blockReason']}');
            }
          }
        }
      }
    } catch (e) {
      yield LlmError('Network Error: Failed to connect to Google Gemini API. $e');
    } finally {
      client.close();
    }
  }

  // ADDED: Helper to build the 'contents' part of the request body
  List<Map<String, dynamic>> _buildContents(List<ChatMessage> history, String prompt) {
    return [
      ...history.map((m) => {
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': [{'text': m.content}]
      }),
      {
        'role': 'user',
        'parts': [{'text': prompt}]
      }
    ];
  }
}