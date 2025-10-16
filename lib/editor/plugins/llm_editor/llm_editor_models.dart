// =========================================
// NEW FILE: lib/editor/plugins/llm_editor/llm_editor_models.dart
// =========================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/plugin_models.dart';
import 'llm_editor_widget.dart';

// Represents a single message in the chat history.
@immutable
class ChatMessage {
  final String role; // e.g., 'user', 'assistant'
  final String content;

  const ChatMessage({required this.role, required this.content});

  ChatMessage copyWith({String? role, String? content}) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
    );
  }
  
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

// The EditorTab implementation for the LLM Editor.
@immutable
class LlmEditorTab extends EditorTab {
  @override
  final GlobalKey<LlmEditorWidgetState> editorKey;

  // The initial list of messages loaded from the .llm file.
  final List<ChatMessage> initialMessages;

  LlmEditorTab({
    required super.plugin,
    required this.initialMessages,
    super.id,
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