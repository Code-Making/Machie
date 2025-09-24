// =========================================
// NEW FILE: lib/editor/plugins/markdown_editor/markdown_editor_widget.dart
// =========================================

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/markdown_editor/markdown_editor_models.dart';

class MarkdownEditorWidget extends ConsumerStatefulWidget {
  final MarkdownEditorTab tab;

  const MarkdownEditorWidget({
    super.key,
    required this.tab,
  });

  @override
  ConsumerState<MarkdownEditorWidget> createState() =>
      _MarkdownEditorWidgetState();
}

class _MarkdownEditorWidgetState extends ConsumerState<MarkdownEditorWidget> {
  late final EditorState editorState;

  @override
  void initState() {
    super.initState();

    // Initialize the AppFlowy editor's core state object with the
    // document that was parsed when the tab was created.
    editorState = EditorState(
      document: widget.tab.initialDocument,
    );
  }

  @override
  void dispose() {
    // It's crucial to dispose the editorState to free up resources.
    editorState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The AppFlowyEditor widget is the heart of the UI.
    return AppFlowyEditor(
      editorState: editorState,
      // We can customize the style later if needed.
      // For now, the default desktop style is fine.
      editorStyle: EditorStyle.desktop(),
    );
  }
}
