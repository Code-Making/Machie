import 'dart:async';
import '../llm_editor_models.dart';
import '../llm_editor_types.dart';
export 'gemini_provider.dart'; 

abstract class LlmProvider {
  String get id;
  String get name;

  /// Fetches available models from the provider.
  Future<List<LlmModelInfo>> listModels();

  /// Streaming response for chat interface.
  /// Implementations MUST support cancellation by cleaning up resources
  /// in the `finally` block of the async* generator.
  Stream<LlmResponseEvent> generateResponse({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  });

  /// Single-shot response for refactoring commands.
  /// Implementations should use retries for robustness.
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
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
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

  @override
  Stream<LlmResponseEvent> generateResponse({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  }) async* {
    final prompt = conversation.last.content;
    final response =
        "This is a streaming dummy response for model **'${model.displayName}'**.\n"
        "Your prompt was: **'$prompt'**.\n\n"
        "Here is a fake code block:\n"
        "```dart\n"
        "void main() {\n"
        "  print('Hello World');\n"
        "}\n"
        "```";
        
    final chunks = response.split(RegExp(r'(?<=\s)')); // Split by words keeping delimiters
    
    for (final chunk in chunks) {
      // Simulate network latency
      await Future.delayed(const Duration(milliseconds: 50));
      yield LlmTextChunk(chunk);
    }

    yield LlmResponseMetadata(
      promptTokenCount: prompt.length ~/ 4,
      responseTokenCount: response.length ~/ 4,
    );
  }

  @override
  Future<String> generateSimpleResponse({
    required String prompt,
    required LlmModelInfo model,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return "/* Dummy Refactor */\n$prompt";
  }
}