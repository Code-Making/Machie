// lib/editor/plugins/refactor_editor/occurrence_list_item.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/default.dart' as default_theme;

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
    final codeThemeData = CodeThemes.availableCodeThemes[settings.themeName] ?? default_theme.defaultTheme;
    final textStyle = TextStyle(fontFamily: settings.fontFamily, fontSize: 13);
    final codeBgColor = codeThemeData['root']?.backgroundColor ?? Colors.black.withOpacity(0.25);
    final occurrence = item.occurrence;

    // --- NEW LOGIC FOR PREVIEW ---

    // 1. Trim leading whitespace and find how much was trimmed.
    final leadingWhitespace = RegExp(r'^\s*');
    final whitespaceMatch = leadingWhitespace.firstMatch(occurrence.lineContent);
    final trimmedCode = occurrence.lineContent.trimLeft();
    final trimmedLength = whitespaceMatch?.group(0)?.length ?? 0;

    // 2. Apply syntax highlighting to the trimmed code.
    LlmHighlightUtil.ensureLanguagesRegistered();
    final languageKey = CodeThemes.inferLanguageKey(occurrence.displayPath);
    final highlightResult = LlmHighlightUtil.highlight.highlight(
      code: trimmedCode,
      language: languageKey,
    );
    final renderer = TextSpanRenderer(textStyle, codeThemeData);
    highlightResult.render(renderer);
    final highlightedSpan = renderer.span ?? TextSpan(text: trimmedCode, style: textStyle);

    // 3. Re-calculate the start/end of the match within the *trimmed* code.
    final matchStartInTrimmed = occurrence.startColumn - trimmedLength;
    final matchEndInTrimmed = matchStartInTrimmed + occurrence.matchedText.length;

    // 4. Build the final TextSpan by overlaying the match highlight.
    // This is more complex because we need to walk the TextSpan tree.
    final previewSpan = TextSpan(
      children: _overlayHighlight(
        source: highlightedSpan,
        start: matchStartInTrimmed,
        end: matchEndInTrimmed,
        highlightStyle: TextStyle(
          backgroundColor: theme.colorScheme.primary.withOpacity(0.5),
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    // --- END NEW LOGIC ---

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    child: Center(child: leadingIcon),
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 5. Prepend the line number.
                            Container(
                              padding: const EdgeInsets.only(right: 12.0),
                              child: Text(
                                '${occurrence.lineNumber + 1}',
                                style: textStyle.copyWith(color: Colors.grey.shade600),
                              ),
                            ),
                            RichText(text: previewSpan),
                          ],
                        ),
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

  /// A helper function to walk a TextSpan tree and apply a highlight style to a specific range.
  List<TextSpan> _overlayHighlight({
    required TextSpan source,
    required int start,
    required int end,
    required TextStyle highlightStyle,
  }) {
    final List<TextSpan> result = [];
    int currentIndex = 0;

    void processSpan(TextSpan span) {
      final spanStart = currentIndex;
      final spanEnd = spanStart + (span.text?.length ?? 0);

      // --- Intersection logic ---
      final highlightStart = start;
      final highlightEnd = end;

      // No overlap
      if (spanEnd <= highlightStart || spanStart >= highlightEnd) {
        result.add(span);
      } else {
        // Overlap exists, break the span into up to 3 parts
        
        // Part 1: Before the highlight
        if (spanStart < highlightStart) {
          result.add(TextSpan(
            text: span.text!.substring(0, highlightStart - spanStart),
            style: span.style,
          ));
        }

        // Part 2: The highlighted section
        final int intersectionStart = (spanStart > highlightStart) ? spanStart : highlightStart;
        final int intersectionEnd = (spanEnd < highlightEnd) ? spanEnd : highlightEnd;
        result.add(TextSpan(
          text: span.text!.substring(intersectionStart - spanStart, intersectionEnd - spanStart),
          style: (span.style ?? const TextStyle()).merge(highlightStyle),
        ));

        // Part 3: After the highlight
        if (spanEnd > highlightEnd) {
          result.add(TextSpan(
            text: span.text!.substring(highlightEnd - spanStart),
            style: span.style,
          ));
        }
      }

      currentIndex = spanEnd;

      if (span.children != null) {
        for (final child in span.children!) {
          if (child is TextSpan) {
            processSpan(child);
          }
        }
      }
    }

    processSpan(source);
    return result;
  }
}