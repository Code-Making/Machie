// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:collection/collection.dart';

// Project imports:
import '../../editor_tab_models.dart';
import '../plugin_models.dart';
import 'llm_editor_widget.dart';

@immutable
class ChatMessage {
  final String role;
  final String content;
  final List<ContextItem>? context;

  final int? totalConversationTokenCount;

  const ChatMessage({
    required this.role,
    required this.content,
    this.context,
    this.totalConversationTokenCount,
  });

  ChatMessage copyWith({
    String? role,
    String? content,
    List<ContextItem>? context,
    int? totalConversationTokenCount,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      context: context ?? this.context,
      totalConversationTokenCount:
          totalConversationTokenCount ?? this.totalConversationTokenCount,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      context:
          (json['context'] as List<dynamic>?)?.map((item) {
            final itemMap = Map<String, dynamic>.from(item);
            return ContextItem(
              source: itemMap['source'],
              content: itemMap['content'],
            );
          }).toList(),
      totalConversationTokenCount: json['totalConversationTokenCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (context != null && context!.isNotEmpty)
      'context':
          context!
              .map((item) => {'source': item.source, 'content': item.content})
              .toList(),
    if (totalConversationTokenCount != null)
      'totalConversationTokenCount': totalConversationTokenCount,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ChatMessage &&
        other.role == role &&
        other.content == content &&
        const DeepCollectionEquality().equals(other.context, context) &&
        other.totalConversationTokenCount == totalConversationTokenCount;
  }

  @override
  int get hashCode {
    return Object.hash(
      role,
      content,
      const DeepCollectionEquality().hash(context),
      totalConversationTokenCount,
    );
  }
}

@immutable
class LlmModelInfo {
  final String name;
  final String displayName;
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
      supportedGenerationMethods:
          (json['supportedGenerationMethods'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'inputTokenLimit': inputTokenLimit,
    'outputTokenLimit': outputTokenLimit,
    'supportedGenerationMethods': supportedGenerationMethods,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmModelInfo &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}

@immutable
class LlmEditorTab extends EditorTab {
  @override
  final GlobalKey<LlmEditorWidgetState> editorKey;

  final List<ChatMessage> initialMessages;

  LlmEditorTab({
    required super.plugin,
    required this.initialMessages,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<LlmEditorWidgetState>();

  @override
  void dispose() {}
}

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
    selectedModels = (json['selectedModels'] as Map<String, dynamic>? ?? {})
        .map(
          (key, value) => MapEntry(
            key,
            value == null
                ? null
                : LlmModelInfo.fromJson(value as Map<String, dynamic>),
          ),
        );
  }

  @override
  Map<String, dynamic> toJson() => {
    'selectedProviderId': selectedProviderId,
    'apiKeys': apiKeys,
    'selectedModels': selectedModels.map(
      (key, value) => MapEntry(key, value?.toJson()),
    )..removeWhere((key, value) => value == null),
  };

  LlmEditorSettings copyWith({
    String? selectedProviderId,
    Map<String, String>? apiKeys,
    Map<String, LlmModelInfo?>? selectedModels,
  }) {
    return LlmEditorSettings(
      selectedProviderId: selectedProviderId ?? this.selectedProviderId,
      apiKeys: apiKeys ?? this.apiKeys,
      selectedModels: selectedModels ?? this.selectedModels,
    );
  }
}

@immutable
class ContextItem {
  final String source;
  final String content;

  const ContextItem({required this.source, required this.content});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ContextItem &&
        other.source == source &&
        other.content == content;
  }

  @override
  int get hashCode => Object.hash(source, content);
}
