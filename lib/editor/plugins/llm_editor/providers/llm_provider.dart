// =========================================
// NEW FILE: lib/editor/plugins/llm_editor/providers/llm_provider.dart
// =========================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';

// Abstract base class for all LLM providers.
abstract class LlmProvider {
  String get id;
  String get name;

  Future<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
  });
}

// A dummy provider for testing without an API key.
class DummyProvider implements LlmProvider {
  @override
  String get id => 'dummy';
  @override
  String get name => 'Dummy (Testing)';

  @override
  Future<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return "This is a dummy response to your prompt: **'$prompt'**. \n\n"
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
  String get name => 'OpenAI (gpt-4o-mini)';

  final String _apiKey;
  OpenAiProvider(this._apiKey);

  @override
  Future<String> generateResponse({
    required List<ChatMessage> history,
    required String prompt,
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
      'model': 'gpt-4o-mini',
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