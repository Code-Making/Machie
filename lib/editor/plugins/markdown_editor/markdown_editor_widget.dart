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
  const MarkdownEditorWidget({ super.key, required this.tab });

  @override
  ConsumerState<MarkdownEditorWidget> createState() => MarkdownEditorWidgetState();
}

class MarkdownEditorWidgetState extends ConsumerState<MarkdownEditorWidget> {
  late final EditorState editorState;
  late final EditorScrollController editorScrollController;

  @override
  void initState() {
    super.initState();
    editorState = EditorState(document: widget.tab.initialDocument);
    editorScrollController = EditorScrollController(editorState: editorState, shrinkWrap: false);
    editorState.transactionStream.listen((_) => ref.read(editorServiceProvider).markCurrentTabDirty());
  }

  @override
  void dispose() {
    editorScrollController.dispose();
    editorState.dispose();
    super.dispose();
  }
  
  String getMarkdownContent() => documentToMarkdown(editorState.document);

  @override
  Widget build(BuildContext context) {
    // This is the new, stable structure. A Column with our fixed toolbar
    // and the editor itself.
    return Column(
      children: [
        Expanded(
          child: AppFlowyEditor(
            editorState: editorState,
            editorScrollController: editorScrollController,
            // Use the new simplified and unified theme
            editorTheme: MarkdownEditorTheme.editorTheme(context),
            editorStyle: MarkdownEditorTheme.getEditorStyle(context),
            blockComponentBuilders: MarkdownEditorTheme.getBlockComponentBuilders(),
          ),
        ),
        // Add our new fixed toolbar at the bottom.
        FixedMarkdownToolbar(editorState: editorState),
      ],
    );
  }
}

// ... (The FixedMarkdownToolbar and _ToolbarButton widgets from Step 1 go here) ...

/// A fixed toolbar for the Markdown editor, adapted from the AppFlowy example.
class FixedMarkdownToolbar extends StatelessWidget {
  final EditorState editorState;

  const FixedMarkdownToolbar({super.key, required this.editorState});

  @override
  Widget build(BuildContext context) {
    // Use a ValueListenableBuilder to rebuild the toolbar when the selection changes.
    // This ensures that buttons like "Bold" correctly show their active state.
    return ValueListenableBuilder(
      valueListenable: editorState.selectionNotifier,
      builder: (context, selection, child) {
        return Container(
          height: 48,
          // Match the app's bottom bar color for consistency.
          color: Theme.of(context).bottomAppBarTheme.color,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Text Style Buttons
                _ToolbarButton(
                  icon: Icons.format_bold,
                  tooltip: 'Bold',
                  isActive: _isTextDecorationActive(editorState, selection, AppFlowyRichTextKeys.bold),
                  onPressed: () => editorState.toggleAttribute(AppFlowyRichTextKeys.bold),
                ),
                _ToolbarButton(
                  icon: Icons.format_italic,
                  tooltip: 'Italic',
                  isActive: _isTextDecorationActive(editorState, selection, AppFlowyRichTextKeys.italic),
                  onPressed: () => editorState.toggleAttribute(AppFlowyRichTextKeys.italic),
                ),
                _ToolbarButton(
                  icon: Icons.format_strikethrough,
                  tooltip: 'Strikethrough',
                  isActive: _isTextDecorationActive(editorState, selection, AppFlowyRichTextKeys.strikethrough),
                  onPressed: () => editorState.toggleAttribute(AppFlowyRichTextKeys.strikethrough),
                ),
                const VerticalDivider(indent: 12, endIndent: 12),
                // Block Style Buttons
                _ToolbarButton(
                  icon: Icons.format_quote,
                  tooltip: 'Quote',
                  isActive: _isBlockTypeActive(editorState, selection, QuoteBlockKeys.type),
                  onPressed: () => editorState.formatNode(selection, (node) => node.copyWith(type: node.type == QuoteBlockKeys.type ? ParagraphBlockKeys.type : QuoteBlockKeys.type)),
                ),
                _ToolbarButton(
                  icon: Icons.format_list_bulleted,
                  tooltip: 'Bulleted List',
                  isActive: _isBlockTypeActive(editorState, selection, BulletedListBlockKeys.type),
                  onPressed: () => editorState.formatNode(selection, (node) => node.copyWith(type: node.type == BulletedListBlockKeys.type ? ParagraphBlockKeys.type : BulletedListBlockKeys.type)),
                ),
                _ToolbarButton(
                  icon: Icons.checklist,
                  tooltip: 'Checklist',
                  isActive: _isBlockTypeActive(editorState, selection, TodoListBlockKeys.type),
                  onPressed: () => editorState.formatNode(selection, (node) => node.copyWith(type: node.type == TodoListBlockKeys.type ? ParagraphBlockKeys.type : TodoListBlockKeys.type)),
                ),
                const VerticalDivider(indent: 12, endIndent: 12),
                // Insert Buttons
                _ToolbarButton(
                  icon: Icons.horizontal_rule,
                  tooltip: 'Divider',
                  onPressed: () {
                    final currentSelection = editorState.selection;
                    if (currentSelection == null) return;
                    final transaction = editorState.transaction;
                    transaction.insertNode(currentSelection.start.path.next, dividerNode());
                    editorState.apply(transaction);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method to check if a text attribute (like bold) is active.
  bool _isTextDecorationActive(EditorState editorState, Selection? selection, String name) {
    selection ??= editorState.selection;
    if (selection == null) return false;
    
    if (selection.isCollapsed) {
      return editorState.toggledStyle.attributes[name] == true;
    } else {
      final nodes = editorState.getNodesInSelection(selection);
      return nodes.allSatisfyInSelection(selection, (delta) {
        return delta.everyAttributes((attributes) => attributes[name] == true);
      });
    }
  }

  // Helper method to check if the current selection is of a specific block type.
  bool _isBlockTypeActive(EditorState editorState, Selection? selection, String type) {
    selection ??= editorState.selection;
    if (selection == null) return false;
    final nodes = editorState.getNodesInSelection(selection);
    return nodes.every((node) => node.type == type);
  }
}

/// A standardized button for the toolbar.
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback? onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.isActive = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      color: isActive ? Theme.of(context).colorScheme.primary : Colors.white70,
    );
  }
}