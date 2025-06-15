// lib/plugins/markdown_editor/markdown_editor_widget.dart
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import 'markdown_editor_models.dart';
import 'markdown_editor_plugin.dart';

class MarkdownEditorWidget extends ConsumerStatefulWidget {
  final MarkdownTab tab;
  final MarkdownEditorPlugin plugin;
  final AppFlowyEditorState editorState;

  const MarkdownEditorWidget({
    super.key,
    required this.tab,
    required this.plugin,
    required this.editorState,
  });

  @override
  ConsumerState<MarkdownEditorWidget> createState() => _MarkdownEditorWidgetState();
}

class _MarkdownEditorWidgetState extends ConsumerState<MarkdownEditorWidget> {
  @override
  void initState() {
    super.initState();
    // Add a listener to notify the plugin of document changes, which in turn
    // marks the tab as dirty.
    widget.editorState.addListener(_onDocumentChanged);
  }

  @override
  void dispose() {
    widget.editorState.removeListener(_onDocumentChanged);
    super.dispose();
  }

  void _onDocumentChanged() {
    // This listener can be used for more than just dirty checking in the future.
    widget.plugin.onDocumentChanged(widget.tab, ref);
  }

  @override
  Widget build(BuildContext context) {
    return AppFlowyEditor(
      editorState: widget.editorState,
      editorStyle: EditorStyle.mobile(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        cursorColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}