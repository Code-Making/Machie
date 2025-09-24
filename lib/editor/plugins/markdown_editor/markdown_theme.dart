// =========================================
// FILE: lib/editor/plugins/markdown_editor/markdown_theme.dart
// =========================================

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart'; // Required for TapGestureRecognizer
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Provides a dark theme configuration for the AppFlowy editor.
class MarkdownEditorTheme {
  
  // ... getEditorStyle() is unchanged and correct ...
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
      textSpanDecorator: (context, node, index, text, before, _) {
        final href = text.attributes?[AppFlowyRichTextKeys.href];
        if (href is String) {
          return TextSpan(
            text: text.text,
            style: before.style,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                debugPrint('Tapped link: $href');
              },
          );
        }
        return before;
      },
    );
  }


  /// Creates a map of customized [BlockComponentBuilder]s for a dark theme.
  static Map<String, BlockComponentBuilder> getBlockComponentBuilders(EditorState editorState) {
    // Start with a mutable copy of the standard builders
    final builders = Map<String, BlockComponentBuilder>.from(standardBlockComponentBuilderMap);

    // Common configuration for padding and placeholder
    final commonConfiguration = BlockComponentConfiguration(
      padding: (node) => const EdgeInsets.symmetric(vertical: 8),
      placeholderText: (node) => 'Type here...',
    );
    
    // --- Customize specific block types by creating NEW instances ---

    // HEADING BLOCK
    final levelToFontSize = [32.0, 24.0, 20.0, 18.0, 16.0, 16.0];
    final levelToFontWeight = [FontWeight.w800, FontWeight.w700, FontWeight.w600, FontWeight.w600, FontWeight.w600, FontWeight.w600];
    final levelToColor = [Colors.white, Colors.grey.shade100, Colors.grey.shade200, Colors.grey.shade300, Colors.grey.shade300, Colors.grey.shade300];

    builders[HeadingBlockKeys.type] = HeadingBlockComponentBuilder(
      textStyleBuilder: (level) {
        return GoogleFonts.inter(
          fontSize: levelToFontSize.elementAt(level - 1),
          fontWeight: levelToFontWeight.elementAt(level - 1),
          color: levelToColor.elementAt(level - 1),
        );
      },
    );

    // QUOTE BLOCK
    builders[QuoteBlockKeys.type] = QuoteBlockComponentBuilder(
      iconBuilder: (context, node) {
        return Container(
          margin: const EdgeInsets.only(right: 8.0),
          width: 4,
          height: node.children.isEmpty ? 20 : null,
          decoration: BoxDecoration(
            color: Colors.grey.shade700,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
    
    // TODO-LIST BLOCK
    builders[TodoListBlockKeys.type] = TodoListBlockComponentBuilder(
      configuration: BlockComponentConfiguration(
        textStyle: (node, {textSpan}) {
          final checked = node.attributes[TodoListBlockKeys.checked] as bool;
          return TextStyle(
            color: checked ? Colors.grey.shade600 : Colors.grey.shade300,
            decoration: checked ? TextDecoration.lineThrough : null,
          );
        },
      ),
      // THE FIX: The EditorState is passed as the third argument directly.
      iconBuilder: (context, node, editorState) {
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
      },
    );

    // THE FIX: Loop through the MODIFIED map and apply the common configuration
    // to each builder's existing configuration.
    for (final key in builders.keys) {
      final builder = builders[key]!;
      builders[key]!.configuration = builder.configuration.copyWith(
        padding: commonConfiguration.padding,
        placeholderText: commonConfiguration.placeholderText,
      );
    }
    
    return builders;
  }
}