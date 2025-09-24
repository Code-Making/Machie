// =========================================
// FILE: lib/editor/plugins/markdown_editor/markdown_editor_widget.dart
// =========================================

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/markdown_editor/markdown_editor_models.dart';
import 'package:machine/editor/plugins/markdown_editor/markdown_theme.dart';
import 'package:machine/editor/services/editor_service.dart'; // <-- ADD THIS IMPORT

class MarkdownEditorWidget extends ConsumerStatefulWidget {
  final MarkdownEditorTab tab;

  const MarkdownEditorWidget({
    super.key,
    required this.tab,
  });

  @override
  ConsumerState<MarkdownEditorWidget> createState() =>
      MarkdownEditorWidgetState();
}

class MarkdownEditorWidgetState extends ConsumerState<MarkdownEditorWidget> {
  late final EditorState editorState;

  @override
  void initState() {
    super.initState();

    editorState = EditorState(
      document: widget.tab.initialDocument,
    );

    // ADDED: Listen for any transaction to mark the tab as dirty.
    editorState.transactionStream.listen((_) {
      // Use the service to mark the current tab as dirty. This will update
      // the UI (like adding a '*' to the tab title) and enable the save button.
      ref.read(editorServiceProvider).markCurrentTabDirty();
    });
  }

  @override
  void dispose() {
    editorState.dispose();
    super.dispose();
  }
  
  // ADDED: A public method accessible via the GlobalKey (editorKey)
  // that the plugin can call to get the current content for saving.
  String getMarkdownContent() {
    return documentToMarkdown(editorState.document);
  }

  @override
  Widget build(BuildContext context) {
    // THE FIX: The MobileToolbarV2 now wraps the AppFlowyEditor,
    // providing it as the required 'child'.
    return MobileToolbarV2(
      editorState: editorState,
      toolbarHeight: 48.0,
      toolbarItems: [
        textDecorationMobileToolbarItemV2,
        buildTextAndBackgroundColorMobileToolbarItem(),
        blocksMobileToolbarItem,
        linkMobileToolbarItem,
        dividerMobileToolbarItem,
      ],
      child: Container(
        color: Theme.of(context).drawerTheme.backgroundColor,
        child: AppFlowyEditor(
          editorState: editorState,
          editorStyle: MarkdownEditorTheme.getEditorStyle(context),
          blockComponentBuilders: MarkdownEditorTheme.getBlockComponentBuilders(),
        ),
      ),
    );
  }
}

// REMOVED: The separate MarkdownToolbar widget is no longer needed.