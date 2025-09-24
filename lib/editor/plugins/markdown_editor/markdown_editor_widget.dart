// =========================================
// FILE: lib/editor/plugins/markdown_editor/markdown_editor_widget.dart
// =========================================

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/markdown_editor/markdown_editor_models.dart';
import 'package:machine/editor/plugins/markdown_editor/markdown_theme.dart';
import 'package:machine/editor/services/editor_service.dart';

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
  late final EditorScrollController editorScrollController;

  @override
  void initState() {
    super.initState();

    editorState = EditorState(
      document: widget.tab.initialDocument,
    );

    editorScrollController = EditorScrollController(
      editorState: editorState,
      shrinkWrap: false,
    );

    editorState.transactionStream.listen((_) {
      ref.read(editorServiceProvider).markCurrentTabDirty();
    });
  }

  @override
  void dispose() {
    editorScrollController.dispose();
    editorState.dispose();
    super.dispose();
  }
  
  String getMarkdownContent() {
    return documentToMarkdown(editorState.document);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // THE FIX: Use a Column to place the editor above the toolbar.
    // The MobileToolbar will then manage its own height relative to the keyboard.
    return Column(
      children: [
        Expanded(
          child: Container(
            color: theme.drawerTheme.backgroundColor,
            child: MobileFloatingToolbar(
              editorState: editorState,
              editorScrollController: editorScrollController,
              floatingToolbarHeight: 42,
              toolbarBuilder: (context, anchor, closeToolbar) {
                return AdaptiveTextSelectionToolbar.editable(
                  clipboardStatus: ClipboardStatus.pasteable,
                  onCopy: () {
                    copyCommand.execute(editorState);
                    closeToolbar();
                  },
                  onCut: () {
                    cutCommand.execute(editorState);
                    closeToolbar();
                  },
                  onPaste: () {
                    pasteCommand.execute(editorState);
                    closeToolbar();
                  },
                  onSelectAll: () => selectAllCommand.execute(editorState),
                  onLiveTextInput: null,
                  onLookUp: null,
                  onSearchWeb: null,
                  onShare: null,
                  anchors: TextSelectionToolbarAnchors(
                    primaryAnchor: anchor,
                  ),
                );
              },
              child: AppFlowyEditor(
                editorState: editorState,
                editorScrollController: editorScrollController,
                editorStyle: MarkdownEditorTheme.getEditorStyle(context),
                blockComponentBuilders: MarkdownEditorTheme.getBlockComponentBuilders(),
                showMagnifier: true,
              ),
            ),
          ),
        ),
        // Use the older, more complex toolbar that correctly handles keyboard height.
        MobileToolbar(
          editorState: editorState,
          toolbarItems: [
            textDecorationMobileToolbarItem, // Note: these are the V1 items
            buildTextAndBackgroundColorMobileToolbarItem(),
            blocksMobileToolbarItem,
            linkMobileToolbarItem,
            dividerMobileToolbarItem,
          ],
          // Pass in colors from our app's theme to style the toolbar.
          backgroundColor: theme.bottomAppBarTheme.color ?? theme.colorScheme.surface,
          foregroundColor: theme.colorScheme.onSurface,
          itemHighlightColor: theme.colorScheme.primary,
          tabbarSelectedBackgroundColor: theme.colorScheme.primary.withOpacity(0.2),
          tabbarSelectedForegroundColor: theme.colorScheme.primary,
        ),
      ],
    );
  }
}