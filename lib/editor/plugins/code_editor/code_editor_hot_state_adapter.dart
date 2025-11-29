// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_editor_hot_state_adapter.dart
// =========================================

import '../../../data/cache/type_adapters.dart';
import 'code_editor_hot_state_dto.dart';

/// A type adapter for serializing and deserializing [CodeEditorHotStateDto].
class CodeEditorHotStateAdapter implements TypeAdapter<CodeEditorHotStateDto> {
  static const String _contentKey = 'content';
  static const String _languageIdKey = 'languageId';
  static const String _hashKey = 'baseContentHash';

  @override
  CodeEditorHotStateDto fromJson(Map<String, dynamic> json) {
    return CodeEditorHotStateDto(
      content: json[_contentKey] as String? ?? '',
      languageId: json[_languageIdKey] as String?,
      baseContentHash: json[_hashKey] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson(CodeEditorHotStateDto object) {
    return {
      _contentKey: object.content,
      _languageIdKey: object.languageId,
      _hashKey: object.baseContentHash,
    };
  }
}
