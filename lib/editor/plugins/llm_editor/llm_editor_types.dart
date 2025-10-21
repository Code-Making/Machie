import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:uuid/uuid.dart';

class DisplayMessage {
  final String id;
  final ChatMessage message;
  final GlobalKey headerKey;
  final List<GlobalKey> codeBlockKeys;
  
  // 1. Add the state properties here.
  final bool isFolded;
  final bool isContextFolded;

  DisplayMessage({
    required this.message,
    required this.headerKey,
    required this.codeBlockKeys,
    String? id,
    // 2. Add them to the constructor with default values.
    this.isFolded = false,
    this.isContextFolded = false,
  }) : id = id ?? const Uuid().v4();

  factory DisplayMessage.fromChatMessage(ChatMessage message) {
    final codeBlockCount = _countCodeBlocks(message.content);
    return DisplayMessage(
      message: message,
      headerKey: GlobalKey(),
      codeBlockKeys: List.generate(codeBlockCount, (_) => GlobalKey(), growable: false),
    );
  }

  DisplayMessage copyWith({
    ChatMessage? message,
    // 3. Add them to copyWith so we can update them.
    bool? isFolded,
    bool? isContextFolded,
  }) {
    return DisplayMessage(
      id: id,
      message: message ?? this.message,
      headerKey: headerKey,
      codeBlockKeys: codeBlockKeys,
      isFolded: isFolded ?? this.isFolded,
      isContextFolded: isContextFolded ?? this.isContextFolded,
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