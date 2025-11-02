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

    return Material(
      color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
      child: InkWell(
        onTap: onJumpTo,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SIMPLIFIED: No longer a ListTile, just the code preview
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sized box to align with checkbox in the header
                  SizedBox(
                    width: 40,
                    child: Center(
                      child: leadingIcon,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
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
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ),
      ),
    );
  }
}