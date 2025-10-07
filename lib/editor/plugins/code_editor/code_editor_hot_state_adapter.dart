import '../../../data/cache/type_adapters.dart';
import 'code_editor_hot_state_dto.dart';

/// A type adapter for serializing and deserializing [CodeEditorHotStateDto].
class CodeEditorHotStateAdapter implements TypeAdapter<CodeEditorHotStateDto> {
  // Define constant keys to avoid magic strings.
  static const String _contentKey = 'content';
  static const String _languageKey = 'languageKey'; // <-- ADDED

  @override
  CodeEditorHotStateDto fromJson(Map<String, dynamic> json) {
    return CodeEditorHotStateDto(
      content: json[_contentKey] as String? ?? '',
      languageKey: json[_languageKey] as String?, // <-- ADDED
    );
  }

  @override
  Map<String, dynamic> toJson(CodeEditorHotStateDto object) {
    return {
      _contentKey: object.content,
      _languageKey: object.languageKey, // <-- ADDED
    };
  }
}
