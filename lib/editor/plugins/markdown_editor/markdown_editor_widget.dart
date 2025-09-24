// =========================================
// FILE: lib/editor/plugins/markdown_editor/markdown_editor_widget.dart
// =========================================

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/markdown_editor/markdown_editor_models.dart';
import 'package:machine/editor/plugins/markdown_editor/markdown_theme.dart'; // <-- ADD THIS IMPORT

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
    editorState = EditorState(
      document: widget.tab.initialDocument,
    );
  }

  @override
  void dispose() {
    editorState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).drawerTheme.backgroundColor,
      child: AppFlowyEditor(
        editorState: editorState,
        editorStyle: MarkdownEditorTheme.getEditorStyle(context),
        // REFACTORED: No longer need to pass editorState here.
        blockComponentBuilders: MarkdownEditorTheme.getBlockComponentBuilders(),
      ),
    );
  }
}