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
  
  // MODIFIED: Replaced individual counts with a single total.
  // This represents the total tokens in the conversation UP TO this message.
  final int? totalConversationTokenCount;

  const ChatMessage({
    required this.role,
    required this.content,
    this.context,
    this.totalConversationTokenCount, // MODIFIED
  });

  ChatMessage copyWith({
    String? role,
    String? content,
    List<ContextItem>? context,
    int? totalConversationTokenCount, // MODIFIED
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      context: context ?? this.context,
      totalConversationTokenCount: totalConversationTokenCount ?? this.totalConversationTokenCount, // MODIFIED
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
      totalConversationTokenCount: json['totalConversationTokenCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (context != null && context!.isNotEmpty)
      'context': context!.map((item) => {'source': item.source, 'content': item.content}).toList(),
    if (totalConversationTokenCount != null) 'totalConversationTokenCount': totalConversationTokenCount,
  };
}

@immutable
class LlmModelInfo {
  final String name; // e.g., models/gemini-1.5-flash-latest
  final String displayName; // e.g., Gemini 1.5 Flash
  final int inputTokenLimit;
  final int outputTokenLimit;
  final List<String> supportedGenerationMethods;

  const LlmModelInfo({
    required this.name,
    required this.displayName,
    required this.inputTokenLimit,
    required this.outputTokenLimit,
    required this.supportedGenerationMethods,
  });

  factory LlmModelInfo.fromJson(Map<String, dynamic> json) {
    return LlmModelInfo(
      name: json['name'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Unknown Model',
      inputTokenLimit: json['inputTokenLimit'] as int? ?? 0,
      outputTokenLimit: json['outputTokenLimit'] as int? ?? 0,
      supportedGenerationMethods: (json['supportedGenerationMethods'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  // ADDED: toJson for serialization
  Map<String, dynamic> toJson() => {
        'name': name,
        'displayName': displayName,
        'inputTokenLimit': inputTokenLimit,
        'outputTokenLimit': outputTokenLimit,
        'supportedGenerationMethods': supportedGenerationMethods,
      };

  // ADDED: Equality operators for use in DropdownButton value
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmModelInfo &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
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
  Map<String, String> apiKeys;
  Map<String, LlmModelInfo?> selectedModels;

  LlmEditorSettings({
    this.selectedProviderId = 'dummy',
    this.apiKeys = const {},
    this.selectedModels = const {},
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    selectedProviderId = json['selectedProviderId'] ?? 'dummy';
    apiKeys = Map<String, String>.from(json['apiKeys'] ?? {});
    selectedModels = (json['selectedModels'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(
        key,
        value == null ? null : LlmModelInfo.fromJson(value as Map<String, dynamic>),
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'selectedProviderId': selectedProviderId,
        'apiKeys': apiKeys,
        'selectedModels': selectedModels
            .map((key, value) => MapEntry(key, value?.toJson()))
            // Filter out any entries that might have a null model
            ..removeWhere((key, value) => value == null),
      };

  LlmEditorSettings copyWith({
    String? selectedProviderId,
    Map<String, String>? apiKeys,
    // MODIFIED: Update copyWith signature.
    Map<String, LlmModelInfo?>? selectedModels,
  }) {
    return LlmEditorSettings(
      selectedProviderId: selectedProviderId ?? this.selectedProviderId,
      apiKeys: apiKeys ?? this.apiKeys,
      // MODIFIED: Update copyWith logic.
      selectedModels: selectedModels ?? this.selectedModels,
    );
  }
}

@immutable
class ContextItem {
  final String source; // e.g., "lib/app/app_notifier.dart"
  final String content;

  const ContextItem({required this.source, required this.content});
}