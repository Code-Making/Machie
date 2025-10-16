// =========================================
// UPDATED: lib/editor/plugins/llm_editor/providers/llm_provider.dart
// =========================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';

// Abstract base class for all LLM providers.
abstract class LlmProvider {
  String get id;
  String get name;
  List<String> get availableModels; // NEW: List of available models

  Future<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId, // NEW: Required modelId
  });
}

// A dummy provider for testing without an API key.
class DummyProvider implements LlmProvider {
  @override
  String get id => 'dummy';
  @override
  String get name => 'Dummy (Testing)';
  @override
  List<String> get availableModels => ['dummy-model']; // NEW

  @override
  Future<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId, // UPDATED
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return "This is a dummy response using model **'$modelId'** to your prompt: **'$prompt'**. \n\n"
        "* It supports markdown!\n"
        "* And lists!\n\n"
        "1. And numbered lists.\n"
        "2. Just like the real thing.\n\n"
        "```dart\nvoid main() {\n  print('Hello from Dummy LLM!');\n}\n```";
  }
}

// A concrete implementation for OpenAI's API.
class OpenAiProvider implements LlmProvider {
  @override
  String get id => 'openai';
  @override
  String get name => 'OpenAI';
  @override
  // NEW: List of some common OpenAI models.
  List<String> get availableModels => [
        'gpt-4o-mini',
        'gpt-4o',
        'gpt-4-turbo',
        'gpt-3.5-turbo',
      ];

  final String _apiKey;
  OpenAiProvider(this._apiKey);

  @override
  Future<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId, // UPDATED
  }) async {
    if (_apiKey.isEmpty) {
      return 'Error: OpenAI API key is not set in the plugin settings.';
    }

    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };
    final body = jsonEncode({
      'model': modelId, // UPDATED: Use the passed-in modelId
      'messages': [
        ...history.map((m) => m.toJson()).toList(),
        {'role': 'user', 'content': prompt},
      ],
    });

    try {
      final response = await http.post(uri, headers: headers, body: body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      } else {
        final errorData = jsonDecode(response.body);
        return 'API Error (${response.statusCode}): ${errorData['error']['message']}';
      }
    } catch (e) {
      return 'Network Error: Failed to connect to OpenAI API. $e';
    }
  }
}

// NEW: A concrete implementation for Google's Gemini API.
class GeminiProvider implements LlmProvider {
  @override
  String get id => 'gemini';
  @override
  String get name => 'Google Gemini';
  @override
  List<String> get availableModels => [
        'gemini-2.5-pro',
        'gemini-1.5-flash-latest',
        'gemini-2.5-flash-latest',
        'gemini-1.5-pro-latest',
        'gemini-1.0-pro',
      ];

  final String _apiKey;
  GeminiProvider(this._apiKey);

  @override
  Future<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
    required String modelId,
  }) async {
    if (_apiKey.isEmpty) {
      return 'Error: Google Gemini API key is not set in the plugin settings.';
    }

    // Gemini has a different API structure. It needs alternating 'user' and 'model' roles.
    final List<Map<String, dynamic>> contents = [];
    for (final message in history) {
      // Ensure roles are 'user' or 'model'
      contents.add({
        'role': message.role == 'assistant' ? 'model' : 'user',
        'parts': [
          {'text': message.content}
        ]
      });
    }
    // Add the current prompt as the last user message.
    contents.add({
      'role': 'user',
      'parts': [
        {'text': prompt}
      ]
    });

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=$_apiKey');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({'contents': contents});

    try {
      final response = await http.post(uri, headers: headers, body: body);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // The response structure is different from OpenAI's.
        return data['candidates'][0]['content']['parts'][0]['text'] as String;
      } else {
        final errorData = jsonDecode(response.body);
        return 'API Error (${response.statusCode}): ${errorData['error']['message']}';
      }
    } catch (e) {
      return 'Network Error: Failed to connect to Google Gemini API. $e';
    }
  }
}