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
    // THE FIX: Wrap the entire editor experience in its own Scaffold.
    // This gives MobileToolbarV2 the clean layout context it needs to
    // show its secondary panels correctly.
    return Scaffold(
      // We set the background to transparent so it blends with the main app theme.
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: MobileToolbarV2(
        editorState: editorState,
        toolbarItems: [
          textDecorationMobileToolbarItemV2,
          buildTextAndBackgroundColorMobileToolbarItem(),
          blocksMobileToolbarItem,
          todoListMobileToolbarItem,
          linkMobileToolbarItem,
          dividerMobileToolbarItem,
        ],
        // The child is now the Column containing the editor itself.
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: Theme.of(context).drawerTheme.backgroundColor,
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
          ],
        ),
      ),
    );
  }
}