// lib/plugins/markdown_editor/markdown_editor_widget.dart
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'markdown_editor_models.dart';
import 'markdown_editor_plugin.dart';

class MarkdownEditorWidget extends ConsumerStatefulWidget {
  final MarkdownTab tab;
  final MarkdownEditorPlugin plugin;
  final EditorState editorState; // CORRECTED: Use the correct `EditorState` class

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
    widget.editorState.addListener(_onDocumentChanged);
  }

  @override
  void dispose() {
    widget.editorState.removeListener(_onDocumentChanged);
    super.dispose();
  }

  void _onDocumentChanged() {
    widget.plugin.onDocumentChanged(widget.tab, ref);
  }

  @override
  Widget build(BuildContext context) {
    // CORRECTED: This now wraps the editor in a MobileToolbarV2 for functionality.
    return MobileToolbarV2(
      toolbarItems: [
        textDecorationMobileToolbarItemV2,
        buildTextAndBackgroundColorMobileToolbarItem(),
        blocksMobileToolbarItem,
      ],
      editorState: widget.editorState,
      child: AppFlowyEditor(
        editorState: widget.editorState,
        // The style is configured directly on the AppFlowyEditor now
        editorStyle: EditorStyle.mobile(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
        ),
        blockComponentBuilders: standardBlockComponentBuilderMap,
      ),
    );
  }
}