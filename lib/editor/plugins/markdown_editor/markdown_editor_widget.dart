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
  late final EditorScrollController editorScrollController; // <-- ADDED

  @override
  void initState() {
    super.initState();

    editorState = EditorState(
      document: widget.tab.initialDocument,
    );

    // ADDED: Initialize the scroll controller. This is crucial for
    // the floating toolbar to know where to position itself.
    editorScrollController = EditorScrollController(
      editorState: editorState,
      shrinkWrap: false, // Use false for expanded editors
    );

    editorState.transactionStream.listen((_) {
      ref.read(editorServiceProvider).markCurrentTabDirty();
    });
  }

  @override
  void dispose() {
    editorScrollController.dispose(); // <-- ADDED
    editorState.dispose();
    super.dispose();
  }
  
  String getMarkdownContent() {
    return documentToMarkdown(editorState.document);
  }

// ... inside _MarkdownEditorWidgetState class ...

  @override
  Widget build(BuildContext context) {
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
        child: MobileFloatingToolbar(
          editorState: editorState,
          editorScrollController: editorScrollController,
          // THE FIX: Provide the required height for the floating toolbar.
          floatingToolbarHeight: 42, // A reasonable default height.
          toolbarBuilder: (context, anchor, closeToolbar) {
            // THE FIX: Provide null for the newly required callbacks.
            // These are platform-specific (mostly iOS) and not essential
            // for the core editing experience we're building.
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
              onLiveTextInput: null, // <-- ADDED
              onLookUp: null,        // <-- ADDED
              onSearchWeb: null,     // <-- ADDED
              onShare: null,         // <-- ADDED
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
    );
  }
}