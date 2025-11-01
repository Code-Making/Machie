// lib/editor/plugins/refactor_editor/occurrence_list_item.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/default.dart';

import '../../../editor/plugins/code_editor/code_themes.dart';
import '../../../editor/plugins/llm_editor/llm_highlight_util.dart';
import '../../../settings/settings_notifier.dart';
import '../../plugins/code_editor/code_editor_models.dart';
import 'refactor_editor_models.dart';

class OccurrenceListItem extends ConsumerWidget {
  final RefactorResultItem item;
  final bool isSelected;
  final ValueChanged<bool?> onSelected;
  final VoidCallback onJumpTo;

  const OccurrenceListItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onSelected,
    required this.onJumpTo,
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
    final occurrence = item.occurrence;

    final languageKey = CodeThemes.inferLanguageKey(occurrence.displayPath);

    LlmHighlightUtil.ensureLanguagesRegistered();
    final result = LlmHighlightUtil.highlight.highlight(
      code: occurrence.lineContent,
      language: languageKey,
    );
    final renderer = TextSpanRenderer(textStyle, codeTheme);
    result.render(renderer);
    final highlightedSpan = renderer.span ?? TextSpan(text: occurrence.lineContent, style: textStyle);

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

    // Build the leading icon based on the item's status
    final Widget leadingIcon;
    switch (item.status) {
      case ResultStatus.pending:
        leadingIcon = Checkbox(value: isSelected, onChanged: onSelected);
        break;
      case ResultStatus.applied:
        leadingIcon = const Icon(Icons.check_circle, color: Colors.green);
        break;
      case ResultStatus.failed:
        leadingIcon = Tooltip(
          message: item.failureReason ?? 'An unknown error occurred.',
          child: const Icon(Icons.error, color: Colors.red),
        );
        break;
    }

    return Container(
      color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: leadingIcon,
            onTap: onJumpTo,
            title: Text(occurrence.displayPath, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Line ${occurrence.lineNumber+1}'),
          ),
          InkWell(
            onTap: onJumpTo,
            child: Padding(
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
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}