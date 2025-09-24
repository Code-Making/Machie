// =========================================
// NEW FILE: lib/editor/plugins/markdown_editor/markdown_theme.dart
// =========================================

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Provides a dark theme configuration for the AppFlowy editor.
class MarkdownEditorTheme {
  
  /// Creates a customized [EditorStyle] for a dark theme.
  static EditorStyle getEditorStyle(BuildContext context) {
    final theme = Theme.of(context);
    return EditorStyle(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      cursorColor: theme.colorScheme.primary,
      selectionColor: theme.colorScheme.primary.withOpacity(0.3),
      dragHandleColor: theme.colorScheme.primary,
      textStyleConfiguration: TextStyleConfiguration(
        text: GoogleFonts.inter(
          fontSize: 16.0,
          color: Colors.grey.shade300,
        ),
        h1: GoogleFonts.inter(
          fontSize: 32.0,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        h2: GoogleFonts.inter(
          fontSize: 24.0,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade100,
        ),
        h3: GoogleFonts.inter(
          fontSize: 20.0,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade200,
        ),
        bold: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        italic: const TextStyle(
          fontStyle: FontStyle.italic,
        ),
        href: TextStyle(
          color: theme.colorScheme.secondary,
          decoration: TextDecoration.underline,
        ),
        code: GoogleFonts.firaCode(
          fontSize: 14.0,
          color: Colors.cyan.shade300,
          backgroundColor: Colors.grey.shade800.withOpacity(0.5),
        ),
      ),
    );
  }

  /// Creates a map of customized [BlockComponentBuilder]s for a dark theme.
  static Map<String, BlockComponentBuilder> getBlockComponentBuilders() {
    // Start with the standard builders
    final standardBuilders = standardBlockComponentBuilderMap;

    // Customize the padding and placeholder for all blocks
    for (final builder in standardBuilders.values) {
      builder.configuration = builder.configuration.copyWith(
        padding: (node) => const EdgeInsets.symmetric(vertical: 8),
        placeholderText: (node) => 'Type here...',
      );
    }
    
    // Customize specific block types
    
    // Quote Block
    final quoteBuilder = standardBuilders[QuoteBlockKeys.type] as QuoteBlockComponentBuilder;
    quoteBuilder.iconBuilder = (context, node) {
      return Container(
        margin: const EdgeInsets.only(right: 8.0),
        width: 4,
        height: node.children.isEmpty ? 20 : null, // Set a min height for empty quotes
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    };

    // Todo-List Block
    final todoBuilder = standardBuilders[TodoListBlockKeys.type] as TodoListBlockComponentBuilder;
    todoBuilder.iconBuilder = (context, node, editorState) {
      final checked = node.attributes[TodoListBlockKeys.checked] as bool;
      return GestureDetector(
        onTap: () {
          final transaction = editorState.transaction;
          transaction.updateNode(node, {TodoListBlockKeys.checked: !checked});
          editorState.apply(transaction);
        },
        child: Icon(
          checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
          size: 20,
          color: checked ? Colors.grey.shade600 : Colors.grey.shade400,
        ),
      );
    };
    // Make the text greyed out when checked
    todoBuilder.configuration = todoBuilder.configuration.copyWith(
      textStyle: (node, {textSpan}) {
        final checked = node.attributes[TodoListBlockKeys.checked] as bool;
        return TextStyle(
          color: checked ? Colors.grey.shade600 : Colors.grey.shade300,
          decoration: checked ? TextDecoration.lineThrough : null,
        );
      },
    );


    return standardBuilders;
  }
}