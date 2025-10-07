// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_editor_hot_state_adapter.dart
// =========================================

import '../../../data/cache/type_adapters.dart';
import 'code_editor_hot_state_dto.dart';

/// A type adapter for serializing and deserializing [CodeEditorHotStateDto].
class CodeEditorHotStateAdapter implements TypeAdapter<CodeEditorHotStateDto> {
  // Define constant keys to avoid magic strings.
  static const String _contentKey = 'content';
  static const String _languageKey = 'languageKey';
  static const String _hashKey = 'baseContentHash'; // <-- ADDED

  @override
  CodeEditorHotStateDto fromJson(Map<String, dynamic> json) {
    return CodeEditorHotStateDto(
      content: json[_contentKey] as String? ?? '',
      languageKey: json[_languageKey] as String?,
      baseContentHash: json[_hashKey] as String?, // <-- ADDED
    );
  }

  @override
  Map<String, dynamic> toJson(CodeEditorHotStateDto object) {
    return {
      _contentKey: object.content,
      _languageKey: object.languageKey,
      _hashKey: object.baseContentHash, // <-- ADDED
    };
  }
}