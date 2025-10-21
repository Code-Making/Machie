import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:uuid/uuid.dart';

class DisplayMessage {
  // 1. Add a final, stable ID.
  final String id;
  final ChatMessage message;
  final GlobalKey headerKey;
  final List<GlobalKey> codeBlockKeys;

  DisplayMessage({
    required this.message,
    required this.headerKey,
    required this.codeBlockKeys,
    // 2. Make the ID parameter optional in the constructor.
    String? id,
  }) : id = id ?? const Uuid().v4(); // Generate a new ID if one isn't provided.

  factory DisplayMessage.fromChatMessage(ChatMessage message) {
    final codeBlockCount = _countCodeBlocks(message.content);
    return DisplayMessage(
      message: message,
      headerKey: GlobalKey(),
      codeBlockKeys: List.generate(codeBlockCount, (_) => GlobalKey(), growable: false),
    );
  }

  DisplayMessage copyWith({ChatMessage? message}) {
    return DisplayMessage(
      // 3. CRUCIAL: Pass the existing ID to the new instance.
      id: id,
      message: message ?? this.message,
      headerKey: headerKey,
      codeBlockKeys: codeBlockKeys,
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