// =========================================
// NEW FILE: lib/editor/plugins/code_editor/code_editor_hot_state_dto.dart
// =========================================

import 'package:flutter/foundation.dart';
import '../../../data/dto/tab_hot_state_dto.dart';

/// A DTO representing the unsaved state of the [CodeEditorPlugin].
@immutable
class CodeEditorHotStateDto implements TabHotStateDto {
  /// The full, unsaved text content of the editor.
  final String content;

  const CodeEditorHotStateDto({required this.content});
}