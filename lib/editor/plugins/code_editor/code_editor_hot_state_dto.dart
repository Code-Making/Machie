// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_editor_hot_state_dto.dart
// =========================================

import 'package:flutter/foundation.dart';

import '../../../data/dto/tab_hot_state_dto.dart';

/// A DTO representing the unsaved state of the [CodeEditorPlugin].
@immutable
class CodeEditorHotStateDto extends TabHotStateDto {
  /// The full, unsaved text content of the editor.
  final String content;

  /// The user-overridden language key for syntax highlighting (e.g., 'dart', 'python').
  /// This is null if the language is just inferred from the file extension.
  final String? languageId;

  const CodeEditorHotStateDto({
    required this.content,
    this.languageId,
    super.baseContentHash,
  });
}
