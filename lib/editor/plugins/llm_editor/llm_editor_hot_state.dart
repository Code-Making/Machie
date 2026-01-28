import 'package:flutter/foundation.dart';

import '../../../data/cache/type_adapters.dart';
import '../../../data/dto/tab_hot_state_dto.dart';
import 'llm_editor_models.dart';

@immutable
class LlmEditorHotStateDto extends TabHotStateDto {
  final List<ChatMessage> messages;
  final String? selectedProviderId;
  final LlmModelInfo? selectedModel;

  const LlmEditorHotStateDto({
    required this.messages,
    this.selectedProviderId,
    this.selectedModel,
    super.baseContentHash,
  });
}

class LlmEditorHotStateAdapter implements TypeAdapter<LlmEditorHotStateDto> {
  static const String _messagesKey = 'messages';
  static const String _hashKey = 'baseContentHash';
  static const String _providerKey = 'selectedProviderId';
  static const String _modelKey = 'selectedModel';

  @override
  LlmEditorHotStateDto fromJson(Map<String, dynamic> json) {
    final messagesJson = json[_messagesKey] as List<dynamic>? ?? [];
    
    LlmModelInfo? model;
    if (json[_modelKey] != null) {
      try {
        model = LlmModelInfo.fromJson(Map<String, dynamic>.from(json[_modelKey]));
      } catch (_) {}
    }

    return LlmEditorHotStateDto(
      messages: messagesJson
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      baseContentHash: json[_hashKey] as String?,
      selectedProviderId: json[_providerKey] as String?,
      selectedModel: model,
    );
  }

  @override
  Map<String, dynamic> toJson(LlmEditorHotStateDto object) {
    return {
      _messagesKey: object.messages.map((m) => m.toJson()).toList(),
      _hashKey: object.baseContentHash,
      _providerKey: object.selectedProviderId,
      _modelKey: object.selectedModel?.toJson(),
    };
  }
}