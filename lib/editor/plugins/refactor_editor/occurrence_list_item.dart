// lib/editor/plugins/refactor_editor/occurrence_list_item.dart

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/default.dart' as default_theme;

import '../../../utils/code_themes.dart';
import '../../../utils/llm_highlight_util.dart';
import '../../../settings/settings_notifier.dart';
import '../../plugins/code_editor/code_editor_models.dart';
import 'refactor_editor_models.dart';

// REFACTORED: Converted to a ConsumerStatefulWidget for performance.
class OccurrenceListItem extends ConsumerStatefulWidget {
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
  ConsumerState<OccurrenceListItem> createState() => _OccurrenceListItemState();
}

class _OccurrenceListItemState extends ConsumerState<OccurrenceListItem> {
  // State variables to hold the computed (expensive) widgets.
  late TextSpan _previewSpan;
  late Widget _leadingIcon;

  @override
  void initState() {
    super.initState();
    // Perform the initial computation.
    _computeRenderData();
  }

  @override
  void didUpdateWidget(covariant OccurrenceListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-compute the render data ONLY if the inputs have actually changed.
    // This is the core of the optimization.
    if (oldWidget.item != widget.item ||
        oldWidget.isSelected != widget.isSelected) {
      _computeRenderData();
    }
  }

  /// Performs all expensive calculations and stores the results in state variables.
  /// This method is designed to be called only when necessary.
  void _computeRenderData() {
    final settings =
        ref.read(
          settingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
          ),
        ) ??
        CodeEditorSettings();
    final codeThemeData =
        CodeThemes.availableCodeThemes[settings.themeName] ??
        default_theme.defaultTheme;
    final textStyle = TextStyle(fontFamily: settings.fontFamily, fontSize: 13);
    final occurrence = widget.item.occurrence;
    final leadingWhitespace = RegExp(r'^\s*');
    final whitespaceMatch = leadingWhitespace.firstMatch(
      occurrence.lineContent,
    );
    final trimmedCode = occurrence.lineContent.trimLeft();
    final trimmedLength = whitespaceMatch?.group(0)?.length ?? 0;
    LlmHighlightUtil.ensureLanguagesRegistered();
    final languageKey = CodeThemes.inferLanguageKey(occurrence.displayPath);
    final highlightResult = LlmHighlightUtil.highlight.highlight(
      code: trimmedCode,
      language: languageKey,
    );
    final renderer = TextSpanRenderer(textStyle, codeThemeData);
    highlightResult.render(renderer);
    final highlightedSpan =
        renderer.span ?? TextSpan(text: trimmedCode, style: textStyle);

    // Revert to the simpler single-highlight logic
    final matchStartInTrimmed = occurrence.startColumn - trimmedLength;
    final matchEndInTrimmed =
        matchStartInTrimmed + occurrence.matchedText.length;

    _previewSpan = TextSpan(
      children: _overlayHighlight(
        source: highlightedSpan,
        start: matchStartInTrimmed,
        end: matchEndInTrimmed,
        highlightStyle: TextStyle(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.5),
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    switch (widget.item.status) {
      case ResultStatus.pending:
        _leadingIcon = Checkbox(
          value: widget.isSelected,
          onChanged: widget.onSelected,
        );
        break;
      case ResultStatus.applied:
        _leadingIcon = const Icon(Icons.check_circle, color: Colors.green);
        break;
      case ResultStatus.failed:
        _leadingIcon = Tooltip(
          message: widget.item.failureReason ?? 'An unknown error occurred.',
          child: const Icon(Icons.error, color: Colors.red),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings =
        ref.watch(
          settingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
          ),
        ) ??
        CodeEditorSettings();
    final codeThemeData =
        CodeThemes.availableCodeThemes[settings.themeName] ??
        default_theme.defaultTheme;
    final textStyle = TextStyle(fontFamily: settings.fontFamily, fontSize: 13);
    final codeBgColor =
        codeThemeData['root']?.backgroundColor ??
        Colors.black.withValues(alpha: 0.25);
    final occurrence = widget.item.occurrence;

    return Material(
      color:
          widget.isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
      child: InkWell(
        onTap: widget.onJumpTo,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 40, child: Center(child: _leadingIcon)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: codeBgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.only(right: 12.0),
                              child: Text(
                                '${occurrence.lineNumber + 1}',
                                style: textStyle.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            RichText(text: _previewSpan),
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

  List<TextSpan> _overlayHighlight({
    required TextSpan source,
    required int start,
    required int end,
    required TextStyle highlightStyle,
  }) {
    final List<TextSpan> result = [];
    int currentIndex = 0;

    void processSpan(TextSpan span) {
      if (span.children != null && span.children!.isNotEmpty) {
        for (final child in span.children!) {
          if (child is TextSpan) processSpan(child);
        }
        return;
      }

      if (span.text == null || span.text!.isEmpty) return;

      final spanText = span.text!;
      final spanStart = currentIndex;
      final spanEnd = spanStart + spanText.length;
      final highlightStart = start;
      final highlightEnd = end;

      if (spanEnd <= highlightStart || spanStart >= highlightEnd) {
        result.add(span);
      } else {
        if (spanStart < highlightStart) {
          result.add(
            TextSpan(
              text: spanText.substring(0, highlightStart - spanStart),
              style: span.style,
            ),
          );
        }
        final int intersectionStart =
            (spanStart > highlightStart) ? spanStart : highlightStart;
        final int intersectionEnd =
            (spanEnd < highlightEnd) ? spanEnd : highlightEnd;
        result.add(
          TextSpan(
            text: spanText.substring(
              intersectionStart - spanStart,
              intersectionEnd - spanStart,
            ),
            style: (span.style ?? const TextStyle()).merge(highlightStyle),
          ),
        );
        if (spanEnd > highlightEnd) {
          result.add(
            TextSpan(
              text: spanText.substring(highlightEnd - spanStart),
              style: span.style,
            ),
          );
        }
      }

      currentIndex = spanEnd;
    }

    processSpan(source);
    return result;
  }
}
