// =========================================
// NEW FILE: lib/editor/plugins/llm_editor/llm_editor_models.dart
// =========================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/plugin_models.dart';
import 'llm_editor_widget.dart';

// Represents a single message in the chat history.
@immutable
class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final List<ContextItem>? context;
  // ADDED: Token counts
  final int? promptTokenCount;
  final int? responseTokenCount;

  const ChatMessage({
    required this.role,
    required this.content,
    this.context,
    this.promptTokenCount, // ADDED
    this.responseTokenCount, // ADDED
  });

  ChatMessage copyWith({
    String? role,
    String? content,
    List<ContextItem>? context,
    int? promptTokenCount, // ADDED
    int? responseTokenCount, // ADDED
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      context: context ?? this.context,
      promptTokenCount: promptTokenCount ?? this.promptTokenCount, // ADDED
      responseTokenCount: responseTokenCount ?? this.responseTokenCount, // ADDED
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      context: (json['context'] as List<dynamic>?)
          ?.map((item) {
            final itemMap = Map<String, dynamic>.from(item);
            return ContextItem(source: itemMap['source'], content: itemMap['content']);
          })
          .toList(),
      // ADDED: Deserialize token counts
      promptTokenCount: json['promptTokenCount'] as int?,
      responseTokenCount: json['responseTokenCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (context != null && context!.isNotEmpty)
      'context': context!.map((item) => {'source': item.source, 'content': item.content}).toList(),
    // ADDED: Serialize token counts
    if (promptTokenCount != null) 'promptTokenCount': promptTokenCount,
    if (responseTokenCount != null) 'responseTokenCount': responseTokenCount,
  };
}

// The EditorTab implementation for the LLM Editor.
@immutable
class LlmEditorTab extends EditorTab {
  @override
  final GlobalKey<LlmEditorWidgetState> editorKey;

  final List<ChatMessage> initialMessages;
  // REMOVED initialComposingPrompt and initialComposingContext

  LlmEditorTab({
    required super.plugin,
    required this.initialMessages,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<LlmEditorWidgetState>();

  @override
  void dispose() {}
}

// The settings model for the LLM Editor.
class LlmEditorSettings extends PluginSettings {
  String selectedProviderId;
  Map<String, String> apiKeys; // Maps provider ID to API key
  Map<String, String> selectedModelIds; // NEW: Maps provider ID to a model ID

  LlmEditorSettings({
    this.selectedProviderId = 'dummy',
    this.apiKeys = const {},
    this.selectedModelIds = const {}, // NEW
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    selectedProviderId = json['selectedProviderId'] ?? 'dummy';
    apiKeys = Map<String, String>.from(json['apiKeys'] ?? {});
    selectedModelIds = Map<String, String>.from(json['selectedModelIds'] ?? {}); // NEW
  }

  @override
  Map<String, dynamic> toJson() => {
        'selectedProviderId': selectedProviderId,
        'apiKeys': apiKeys,
        'selectedModelIds': selectedModelIds, // NEW
      };

  LlmEditorSettings copyWith({
    String? selectedProviderId,
    Map<String, String>? apiKeys,
    Map<String, String>? selectedModelIds, // NEW
  }) {
    return LlmEditorSettings(
      selectedProviderId: selectedProviderId ?? this.selectedProviderId,
      apiKeys: apiKeys ?? this.apiKeys,
      selectedModelIds: selectedModelIds ?? this.selectedModelIds, // NEW
    );
  }
}

@immutable
class ContextItem {
  final String source; // e.g., "lib/app/app_notifier.dart"
  final String content;

  const ContextItem({required this.source, required this.content});
}