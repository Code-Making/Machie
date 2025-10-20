// FILE: lib/editor/plugins/llm_editor/llm_editor_types.dart

import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';

class DisplayMessage {
  final ChatMessage message;
  final GlobalKey headerKey;
  final List<GlobalKey> codeBlockKeys;

  DisplayMessage({
    required this.message,
    required this.headerKey,
    required this.codeBlockKeys,
  });

  factory DisplayMessage.fromChatMessage(ChatMessage message) {
    final codeBlockCount = _countCodeBlocks(message.content);
    return DisplayMessage(
      message: message,
      headerKey: GlobalKey(),
      codeBlockKeys: List.generate(codeBlockCount, (_) => GlobalKey(), growable: false),
    );
  }
}

// ADDED: Sealed class for richer stream responses
@immutable
sealed class LlmResponseEvent {}

class LlmTextChunk extends LlmResponseEvent {
  final String chunk;
  LlmTextChunk(this.chunk);
}

class LlmResponseMetadata extends LlmResponseEvent {
  final int promptTokenCount;
  final int responseTokenCount;
  LlmResponseMetadata({required this.promptTokenCount, required this.responseTokenCount});
}

class LlmError extends LlmResponseEvent {
  final String message;
  LlmError(this.message);
}

int _countCodeBlocks(String markdownText) {
  final RegExp codeBlockRegex = RegExp(r'```[\s\S]*?```');
  return codeBlockRegex.allMatches(markdownText).length;
}