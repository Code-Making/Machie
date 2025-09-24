// =========================================
// FILE: lib/editor/plugins/markdown_editor/markdown_theme.dart
// =========================================

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package.flutter/gestures.dart';
import 'package.flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MarkdownEditorTheme {
  
  // This is the core of the new theme strategy.
  // It provides a consistent dark look and feel for the entire editor canvas.
  static EditorTheme editorTheme(BuildContext context) {
    final theme = Theme.of(context);
    return EditorTheme(
      // Background color for the entire editor
      backgroundColor: theme.drawerTheme.backgroundColor ?? const Color(0xFF212121),
      // Default text color
      textColor: Colors.grey.shade300,
      // Color for block elements like dividers and quote bars
      blockColor: Colors.grey.shade700,
      // Placeholder text color
      placeholderTextColor: Colors.grey.shade600,
      // Padding for the entire document canvas
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    );
  }

  static EditorStyle getEditorStyle(BuildContext context) {
    final theme = Theme.of(context);
    return EditorStyle(
      padding: EdgeInsets.zero, // Padding is now handled by EditorTheme
      cursorColor: theme.colorScheme.primary,
      selectionColor: theme.colorScheme.primary.withOpacity(0.3),
      textStyleConfiguration: TextStyleConfiguration(
        text: GoogleFonts.inter(fontSize: 16.0),
        bold: const TextStyle(fontWeight: FontWeight.bold),
        code: GoogleFonts.firaCode(fontSize: 14.0, backgroundColor: Colors.grey.shade800.withOpacity(0.5)),
        href: TextStyle(color: theme.colorScheme.secondary, decoration: TextDecoration.underline),
      ),
      textSpanDecorator: (context, node, index, text, before, _) {
        final href = text.attributes?[AppFlowyRichTextKeys.href];
        if (href is String) {
          return TextSpan(
            text: text.text,
            style: before.style,
            recognizer: TapGestureRecognizer()..onTap = () => debugPrint('Tapped link: $href'),
          );
        }
        return before;
      },
    );
  }

  // We still need custom builders, but only for things the EditorTheme can't handle,
  // like the checkbox icon and heading font sizes.
  static Map<String, BlockComponentBuilder> getBlockComponentBuilders() {
    final builders = Map<String, BlockComponentBuilder>.from(standardBlockComponentBuilderMap);

    // Headings
    final levelToFontSize = [32.0, 24.0, 20.0, 18.0, 16.0, 16.0];
    final levelToFontWeight = [FontWeight.w800, FontWeight.w700, FontWeight.w600, FontWeight.w600, FontWeight.w600, FontWeight.w600];
    builders[HeadingBlockKeys.type] = HeadingBlockComponentBuilder(
      textStyleBuilder: (level) => GoogleFonts.inter(
        fontSize: levelToFontSize.elementAt(level - 1),
        fontWeight: levelToFontWeight.elementAt(level - 1),
      ),
    );

    // Todo-List Checkbox Icon
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