// =========================================
// FILE: lib/editor/plugins/markdown_editor/markdown_theme.dart
// =========================================

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MarkdownEditorTheme {
  
  // THEME SOURCE OF TRUTH: All colors and text styles are defined here.
  static EditorStyle getEditorStyle(BuildContext context) {
    final theme = Theme.of(context);
    return EditorStyle(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      cursorColor: theme.colorScheme.primary,
      selectionColor: theme.colorScheme.primary.withOpacity(0.4),
      dragHandleColor: theme.colorScheme.primary,
      textStyleConfiguration: TextStyleConfiguration(
        text: GoogleFonts.inter(
          fontSize: 16.0,
          color: Colors.grey.shade300,
          height: 1.5, // Set a consistent line height
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
              ..onTap = () => debugPrint('Tapped link: $href'),
          );
        }
        return before;
      },
    );
  }

  // SIMPLIFIED: We only override builders for special functionality, not styling.
  static Map<String, BlockComponentBuilder> getBlockComponentBuilders() {
    final builders = Map<String, BlockComponentBuilder>.from(standardBlockComponentBuilderMap);

    // Override only the TodoList to provide our custom dark-mode icon.
    // All other blocks will use the default builder, which will automatically
    // pick up the styles from our EditorStyle.
    builders[TodoListBlockKeys.type] = TodoListBlockComponentBuilder(
      iconBuilder: (BuildContext context, Node node, VoidCallback onCheck) {
        final checked = node.attributes[TodoListBlockKeys.checked] as bool;
        return GestureDetector(
          onTap: onCheck,
          child: Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: checked ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
          ),
        );
      },
    );
    
    return builders;
  }
}