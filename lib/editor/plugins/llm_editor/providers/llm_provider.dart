// =========================================
// UPDATED: lib/editor/plugins/llm_editor/providers/llm_provider.dart
// =========================================

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llm_editor_models.dart';

import '../llm_editor_types.dart'; // ADDED

abstract class LlmProvider {
  String get id;
  String get name;

  Future<List<LlmModelInfo>> listModels();

  Stream<LlmResponseEvent> generateResponse({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  });

  Future<String> generateSimpleResponse({
    required String prompt,
    required LlmModelInfo model,
  });

  Future<int> countTokens({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  });
}

class DummyProvider implements LlmProvider {
  @override
  String get id => 'dummy';
  @override
  String get name => 'Dummy (Testing)';
  @override
  Future<List<LlmModelInfo>> listModels() async {
    return [
      const LlmModelInfo(
        name: 'models/dummy-model',
        displayName: 'Dummy Model',
        inputTokenLimit: 819200,
        outputTokenLimit: 1000000,
        supportedGenerationMethods: [
          'generateContent',
          'streamGenerateContent',
        ],
      ),
    ];
  }

  // ADDED: Dummy implementation for countTokens
  @override
  Future<int> countTokens({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  }) async {
    final totalChars = conversation.fold<int>(
      0,
      (sum, msg) => sum + msg.content.length,
    );
    return (totalChars / 4).ceil();
  }

  // MODIFIED: Dummy implementation for the new stream type
  @override
  Stream<LlmResponseEvent> generateResponse({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  }) async* {
    // The last message is the new prompt
    final prompt = conversation.last.content;
    final response =
        "This is a streaming dummy response for model **'${model.displayName}'** to your prompt: **'$prompt'**...";
    final words = response.split(' ');
    for (final word in words) {
      await Future.delayed(const Duration(milliseconds: 5));
      yield LlmTextChunk('$word ');
    }

    final totalPromptTokens =
        (conversation.fold<int>(0, (sum, msg) => sum + msg.content.length) / 4)
            .ceil();
    final responseTokens = (response.length / 4).ceil();

    yield LlmResponseMetadata(
      promptTokenCount: totalPromptTokens,
      responseTokenCount: responseTokens,
    );
  }

  @override
  Future<String> generateSimpleResponse({
    required String prompt,
    required LlmModelInfo model,
  }) async {
    // Simulate a markdown response for testing the parser.
    return Future.value(
      "Sure, here is the modified code block as requested:\n\n"
      "```dart\n"
      "/* This model is for testing. Your prompt was: '$prompt' */\n"
      "```\n\n"
      "I hope this helps!",
    );
  }
}

// A concrete implementation for Google's Gemini API.
class GeminiProvider implements LlmProvider {
  @override
  String get id => 'gemini';
  @override
  String get name => 'Google Gemini';
  @override
  Future<List<LlmModelInfo>> listModels() async {
    if (_cachedModels != null) {
      return _cachedModels!;
    }
    if (_apiKey.isEmpty) {
      return [];
    }

    final client = http.Client();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models',
    );
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    try {
      final response = await client.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final modelsList =
            (json['models'] as List<dynamic>)
                .map((modelJson) => LlmModelInfo.fromJson(modelJson))
                // IMPORTANT: Only keep models that support the streaming method we use.
                .where(
                  (model) => model.supportedGenerationMethods.contains(
                    'generateContent',
                  ),
                )
                .where(
                  (model) =>
                      model.supportedGenerationMethods.contains('countTokens'),
                )
                .toList();

        // Sort to have 'flash' models appear first as they are often preferred for chat.
        modelsList.sort((a, b) {
          if (a.displayName.contains('Flash') &&
              !b.displayName.contains('Flash'))
            return -1;
          if (!a.displayName.contains('Flash') &&
              b.displayName.contains('Flash'))
            return 1;
          return a.displayName.compareTo(b.displayName);
        });

        _cachedModels = modelsList;
        return modelsList;
      } else {
        // Log error or handle it appropriately
        return [];
      }
    } catch (e) {
      return [];
    } finally {
      client.close();
    }
  }

  final String _apiKey;
  List<LlmModelInfo>? _cachedModels;

  GeminiProvider(this._apiKey);

  // ADDED: Full implementation for countTokens
  @override
  Future<int> countTokens({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  }) async {
    if (_apiKey.isEmpty) return 0;

    final client = http.Client();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/${model.name}:countTokens',
    );
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    // MODIFIED: Build contents from the entire conversation
    final contents = _buildContents(conversation);
    final body = jsonEncode({'contents': contents});

    try {
      final response = await client.post(uri, headers: headers, body: body);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['totalTokens'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    } finally {
      client.close();
    }
  }

  // MODIFIED: Full implementation for the new stream type
  @override
  Stream<LlmResponseEvent> generateResponse({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  }) async* {
    if (_apiKey.isEmpty) {
      yield LlmError(
        'Error: Google Gemini API key is not set in the plugin settings.',
      );
      return;
    }

    final client = http.Client();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/${model.name}:streamGenerateContent?alt=sse',
    );
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    // MODIFIED: Build contents from the entire conversation directly
    final contents = _buildContents(conversation);
    final body = jsonEncode({'contents': contents});

    try {
      final request =
          http.Request('POST', uri)
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

            final textContent =
                json['candidates']?[0]?['content']?['parts']?[0]?['text'];
            if (textContent != null) {
              yield LlmTextChunk(textContent as String);
            }

            final usageMetadata = json['usageMetadata'];
            if (usageMetadata != null) {
              yield LlmResponseMetadata(
                promptTokenCount:
                    usageMetadata['promptTokenCount'] as int? ?? 0,
                responseTokenCount:
                    usageMetadata['candidatesTokenCount'] as int? ?? 0,
              );
            }

            final promptFeedback = json['promptFeedback'];
            if (promptFeedback != null &&
                promptFeedback['blockReason'] != null) {
              yield LlmError(
                'Prompt blocked due to: ${promptFeedback['blockReason']}',
              );
            }
          }
        }
      }
    } catch (e) {
      yield LlmError(
        'Network Error: Failed to connect to Google Gemini API. $e',
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<String> generateSimpleResponse({
    required String prompt,
    required LlmModelInfo model,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Google Gemini API key is not set.');
    }

    final client = http.Client();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/${model.name}:generateContent',
    );
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    // Note: We are no longer sending 'responseSchema'.
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        // We can keep this to encourage JSON-like output, but we won't rely on it.
        'responseMimeType': 'text/plain',
      },
    });

    try {
      final response = await client.post(uri, headers: headers, body: body);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        // Extract the plain text response which should contain markdown.
        final content =
            jsonResponse['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (content != null) {
          return content as String;
        } else {
          // Check for blocked content
          final blockReason = jsonResponse['promptFeedback']?['blockReason'];
          if (blockReason != null) {
            throw Exception('Prompt was blocked by the API: $blockReason');
          }
          throw Exception('Invalid response structure from Gemini API.');
        }
      } else {
        throw Exception('API Error (${response.statusCode}): ${response.body}');
      }
    } finally {
      client.close();
    }
  }
}

List<Map<String, dynamic>> _buildContents(List<ChatMessage> conversation) {
  return conversation.map((m) {
    final parts = <Map<String, String>>[
      {'text': m.content},
    ];
    // Context is normalized and included in the 'parts' for user messages.
    if (m.role == 'user' && m.context != null && m.context!.isNotEmpty) {
      final contextText = m.context!
          .map((item) {
            return '--- CONTEXT FILE: ${item.source} ---\n```\n${item.content}\n```';
          })
          .join('\n\n');
      parts.insert(0, {
        'text':
            "Use the following files as context for my request:\n\n$contextText\n\n--- END OF CONTEXT ---\n\n",
      });
    }
    return {'role': m.role == 'assistant' ? 'model' : 'user', 'parts': parts};
  }).toList();
}
