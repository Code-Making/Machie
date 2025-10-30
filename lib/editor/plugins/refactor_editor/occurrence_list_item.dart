// =========================================
// UPDATED: lib/editor/plugins/refactor_editor/occurrence_list_item.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/re_highlight.dart'; // <-- 1. FIX: ADD THE MISSING IMPORT
import 'package:re_highlight/styles/default.dart';

import '../../../editor/plugins/code_editor/code_themes.dart';
import '../../../editor/plugins/llm_editor/llm_highlight_util.dart';
import '../../../settings/settings_notifier.dart';
import '../../plugins/code_editor/code_editor_models.dart';
import 'refactor_editor_models.dart';

// The rest of the file is correct and remains unchanged.
class OccurrenceListItem extends ConsumerWidget {
  final RefactorOccurrence occurrence;
  final bool isSelected;
  final ValueChanged<bool?> onSelected;

  const OccurrenceListItem({
    super.key,
    required this.occurrence,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider.select(
      (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
    )) ?? CodeEditorSettings();
    final codeTheme = CodeThemes.availableCodeThemes[settings.themeName] ?? defaultTheme;
    final textStyle = TextStyle(fontFamily: settings.fontFamily, fontSize: 13);
    final codeBgColor = codeTheme['root']?.backgroundColor ?? Colors.black.withOpacity(0.25);

    final languageKey = CodeThemes.inferLanguageKey(occurrence.displayPath);

    LlmHighlightUtil.ensureLanguagesRegistered();
    final result = LlmHighlightUtil.highlight.highlight(
      code: occurrence.lineContent,
      language: languageKey,
    );
    // 2. FIX: TextSpanRenderer is now available via the import.
    final renderer = TextSpanRenderer(textStyle, codeTheme);
    result.render(renderer);
    final highlightedSpan = renderer.span ?? TextSpan(text: occurrence.lineContent, style: textStyle);

    // Build the RichText with the specific match highlighted
    final matchStart = occurrence.startColumn;
    final matchEnd = matchStart + occurrence.matchedText.length;
    final beforeText = occurrence.lineContent.substring(0, matchStart);
    final afterText = occurrence.lineContent.substring(matchEnd);

    final previewSpan = TextSpan(
      style: textStyle.copyWith(color: codeTheme['root']?.color),
      children: [
        TextSpan(text: beforeText),
        TextSpan(
          text: occurrence.matchedText,
          style: TextStyle(
            backgroundColor: theme.colorScheme.primary.withOpacity(0.5),
            fontWeight: FontWeight.bold,
          ),
        ),
        TextSpan(text: afterText),
      ],
    );

    return Container(
      color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: Checkbox(value: isSelected, onChanged: onSelected),
            title: Text(occurrence.displayPath, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Line ${occurrence.lineNumber}'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: codeBgColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: RichText(text: previewSpan),
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}