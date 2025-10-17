// FINAL CORRECTED FILE: lib/editor/plugins/llm_editor/llm_editor_hot_state.dart

import 'package:machine/data/cache/type_adapters.dart';
import 'package:machine/data/dto/tab_hot_state_dto.dart';
import 'package:flutter/foundation.dart';
import 'llm_editor_models.dart';

@immutable
class LlmEditorHotStateDto extends TabHotStateDto {
  final List<ChatMessage> messages;
  // REMOVED composingPrompt and composingContext

  const LlmEditorHotStateDto({
    required this.messages,
    super.baseContentHash,
  });
}

class LlmEditorHotStateAdapter implements TypeAdapter<LlmEditorHotStateDto> {
  static const String _messagesKey = 'messages';
  static const String _hashKey = 'baseContentHash';
  // REMOVED _promptKey and _contextKey

  @override
  LlmEditorHotStateDto fromJson(Map<String, dynamic> json) {
    final messagesJson = json[_messagesKey] as List<dynamic>? ?? [];
    return LlmEditorHotStateDto(
      messages: messagesJson.map((m) => ChatMessage.fromJson(m)).toList(),
      baseContentHash: json[_hashKey] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson(LlmEditorHotStateDto object) {
    return {
      _messagesKey: object.messages.map((m) => m.toJson()).toList(),
      _hashKey: object.baseContentHash,
    };
  }
}