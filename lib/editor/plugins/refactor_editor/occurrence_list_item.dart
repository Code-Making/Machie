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
  
  static final List<Color> _groupColors = List.generate(10, (index) {
    return HSLColor.fromAHSL(
      0.5, // Alpha (opacity)
      (index * 360 / 10) % 360, // Hue (spread across the color wheel)
      0.8, // Saturation
      0.5, // Lightness
    ).toColor();
  });

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
    final settings = ref.read(settingsProvider.select(
      (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
    )) ?? CodeEditorSettings();
    final codeThemeData = CodeThemes.availableCodeThemes[settings.themeName] ?? default_theme.defaultTheme;
    final textStyle = TextStyle(fontFamily: settings.fontFamily, fontSize: 13);
    final occurrence = widget.item.occurrence;

    final leadingWhitespace = RegExp(r'^\s*');
    final whitespaceMatch = leadingWhitespace.firstMatch(occurrence.lineContent);
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
    final highlightedSpan = renderer.span ?? TextSpan(text: trimmedCode, style: textStyle);

    // UPDATED: Use the new build method for highlighting.
    _previewSpan = TextSpan(
      children: _buildHighlightedSpan(
        source: highlightedSpan,
        occurrence: occurrence,
        trimOffset: trimmedLength,
      ),
    );

    switch (widget.item.status) {
      case ResultStatus.pending:
        _leadingIcon = Checkbox(value: widget.isSelected, onChanged: widget.onSelected);
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
    final settings = ref.watch(settingsProvider.select(
      (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
    )) ?? CodeEditorSettings();
    final codeThemeData = CodeThemes.availableCodeThemes[settings.themeName] ?? default_theme.defaultTheme;
    final textStyle = TextStyle(fontFamily: settings.fontFamily, fontSize: 13);
    final codeBgColor = codeThemeData['root']?.backgroundColor ?? Colors.black.withOpacity(0.25);
    final occurrence = widget.item.occurrence;

    return Material(
      color: widget.isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
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
                  SizedBox(
                    width: 40,
                    child: Center(child: _leadingIcon),
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
                            Container(
                              padding: const EdgeInsets.only(right: 12.0),
                              child: Text(
                                '${occurrence.lineNumber + 1}',
                                style: textStyle.copyWith(color: Colors.grey.shade600),
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

  /// A robust recursive function to traverse a TextSpan tree, apply a highlight
  /// to a specific range, and return the new list of TextSpans.
  List<TextSpan> _buildHighlightedSpan({
    required TextSpan source,
    required RefactorOccurrence occurrence,
    required int trimOffset,
  }) {
    final regions = <({int start, int end, TextStyle style})>[];
    // Add the main match highlight.
    regions.add((
      start: occurrence.startColumn,
      end: occurrence.startColumn + occurrence.matchedText.length,
      style: TextStyle(backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.3))
    ));
    // Add highlights for each captured group.
    for (int i = 0; i < occurrence.capturedGroups.length; i++) {
      final group = occurrence.capturedGroups[i];
      regions.add((
        start: group.startColumn,
        end: group.startColumn + group.text.length,
        style: TextStyle(backgroundColor: _groupColors[i % _groupColors.length])
      ));
    }

    final List<TextSpan> result = [];
    int globalOffset = 0;

    void processSpan(TextSpan span) {
      if (span.children != null && span.children!.isNotEmpty) {
        for (final child in span.children!) {
          if (child is TextSpan) processSpan(child);
        }
        return;
      }

      if (span.text == null || span.text!.isEmpty) return;

      final spanText = span.text!;
      // The span's coordinates are relative to the start of the trimmed string.
      final spanStart = globalOffset;
      final spanEnd = spanStart + spanText.length;
      
      // The highlight region coordinates are relative to the start of the full, untrimmed line.
      // We must adjust them to be relative to the trimmed string.
      final adjustedRegions = regions.map((r) => (
        start: r.start - trimOffset,
        end: r.end - trimOffset,
        style: r.style
      )).toList();

      final cutPoints = <int>{0, spanText.length};
      for (final region in adjustedRegions) {
        if (region.start > spanStart && region.start < spanEnd) {
          cutPoints.add(region.start - spanStart);
        }
        if (region.end > spanStart && region.end < spanEnd) {
          cutPoints.add(region.end - spanStart);
        }
      }
      
      final sortedPoints = cutPoints.toList()..sort();

      for (int i = 0; i < sortedPoints.length - 1; i++) {
        final start = sortedPoints[i];
        final end = sortedPoints[i+1];
        if (start >= end) continue;

        final segmentText = spanText.substring(start, end);
        final segmentMidpoint = spanStart + start + (segmentText.length / 2);

        TextStyle finalStyle = span.style ?? const TextStyle();
        for (final region in adjustedRegions) {
          if (segmentMidpoint >= region.start && segmentMidpoint < region.end) {
            finalStyle = finalStyle.merge(region.style);
          }
        }
        
        result.add(TextSpan(text: segmentText, style: finalStyle));
      }
      
      globalOffset += spanText.length;
    }

    processSpan(source);
    return result;
  }
}
