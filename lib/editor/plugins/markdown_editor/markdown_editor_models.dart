// =========================================
// NEW FILE: lib/editor/plugins/markdown_editor/markdown_editor_models.dart
// =========================================

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:machine/editor/editor_tab_models.dart';

@immutable
class MarkdownEditorTab extends EditorTab {
  final Document initialDocument;

  MarkdownEditorTab({
    required super.plugin,
    required this.initialDocument,
    super.id,
  });

  @override
  void dispose() {
    // No specific resources to dispose for this tab model.
  }
}