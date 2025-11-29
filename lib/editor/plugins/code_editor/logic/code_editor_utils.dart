// =========================================
// NEW: lib/editor/plugins/code_editor/logic/code_editor_utils.dart
// =========================================

import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../../services/language/language_models.dart';
import 'code_editor_types.dart';

/// A utility class containing helper functions for the CodeEditorMachineState.
/// This includes logic for bracket matching, syntax highlighting enhancements,
/// and text manipulation.
class CodeEditorUtils {
  // --- Bracket Matching Logic ---

  /// Calculates the positions of matching brackets around the cursor.
  static BracketHighlightState calculateBracketHighlights(
    CodeLineEditingController controller,
  ) {
    final selection = controller.selection;
    if (!selection.isCollapsed) {
      return const BracketHighlightState();
    }
    final position = selection.base;
    final brackets = {'(': ')', '[': ']', '{': '}'};
    final line = controller.codeLines[position.index].text;
    Set<CodeLinePosition> newPositions = {};
    Set<int> newHighlightedLines = {};
    for (int offset in [position.offset, position.offset - 1]) {
      if (offset >= 0 && offset < line.length) {
        final char = line[offset];
        if (brackets.keys.contains(char) || brackets.values.contains(char)) {
          final currentPosition = CodeLinePosition(
            index: position.index,
            offset: offset,
          );
          final matchPosition = _findMatchingBracket(
            controller.codeLines,
            currentPosition,
            brackets,
          );
          if (matchPosition != null) {
            newPositions.add(currentPosition);
            newPositions.add(matchPosition);
            newHighlightedLines.add(currentPosition.index);
            newHighlightedLines.add(matchPosition.index);
            break;
          }
        }
      }
    }
    return BracketHighlightState(
      bracketPositions: newPositions,
      highlightedLines: newHighlightedLines,
    );
  }

  /// Helper to find a matching bracket, used by [calculateBracketHighlights].
  static CodeLinePosition? _findMatchingBracket(
    CodeLines codeLines,
    CodeLinePosition position,
    Map<String, String> brackets,
  ) {
    final line = codeLines[position.index].text;
    final char = line[position.offset];
    final isOpen = brackets.keys.contains(char);
    final target =
        isOpen
            ? brackets[char]
            : brackets.keys.firstWhere(
              (k) => brackets[k] == char,
              orElse: () => '',
            );
    if (target?.isEmpty ?? true) return null;

    int stack = 1;
    int index = position.index;
    int offset = position.offset;
    final direction = isOpen ? 1 : -1;

    while (true) {
      offset += direction;

      while (offset < 0 || offset >= codeLines[index].text.length) {
        if (direction > 0) {
          index++;
          if (index >= codeLines.length) return null;
          offset = 0;
        } else {
          index--;
          if (index < 0) return null;
          offset = codeLines[index].text.length - 1;
        }
      }

      final currentChar = codeLines[index].text[offset];

      if (currentChar == char) {
        stack++;
      } else if (currentChar == target) {
        stack--;
      }

      if (stack == 0) {
        return CodeLinePosition(index: index, offset: offset);
      }
    }
  }

  // --- Highlight Span Builder Pipeline ---

  /// The main entry point for building the enhanced TextSpan for a line.
  /// This pipeline adds tappable import links, color code previews, and bracket highlights.
  static TextSpan buildHighlightingSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
    required BracketHighlightState bracketHighlightState,
    required void Function(String) onImportTap,
    void Function(int lineIndex, ColorMatch match)? onColorCodeTap,
    required LanguageConfig languageConfig,
  }) {
    // Pipeline Step 1: Add tappable links to import paths.
    final linkedSpan = _linkifyImportPaths(
      codeLine,
      textSpan,
      style,
      onImportTap,
      languageConfig,
    );
    // Pipeline Step 2: Highlight color codes
    final rainbowSpan = _highlightColorCodes(
      codeLine,
      linkedSpan,
      style,
      onColorCodeTap != null ? (match) => onColorCodeTap(index, match) : null,
    );
    // Pipeline Step 3: Highlight matching brackets
    final finalSpan = _highlightBrackets(
      index,
      rainbowSpan,
      style,
      bracketHighlightState,
    );

    return finalSpan;
  }

  /// PIPELINE STEP 1: Finds import paths and makes them tappable.
  static TextSpan _linkifyImportPaths(
    CodeLine codeLine,
    TextSpan textSpan,
    TextStyle style,
    void Function(String) onImportTap,
    LanguageConfig config,
  ) {
    final text = codeLine.text;
    if (!(text.startsWith('import') ||
        text.startsWith('export') ||
        text.startsWith('part'))) {
      return textSpan;
    }
    if (text.contains(':')) return textSpan;
    int quote1Index = text.indexOf("'");
    String quoteChar = "'";
    if (quote1Index == -1) {
      quote1Index = text.indexOf('"');
      quoteChar = '"';
    }
    if (quote1Index == -1) return textSpan;
    final quote2Index = text.indexOf(quoteChar, quote1Index + 1);
    if (quote2Index == -1) return textSpan;
    final pathStartIndex = quote1Index + 1;
    final pathEndIndex = quote2Index;
    if (pathStartIndex >= pathEndIndex) return textSpan;

    List<TextSpan> walkAndReplace(TextSpan span, int currentPos) {
      final List<TextSpan> newChildren = [];
      final spanStart = currentPos;
      final spanText = span.text ?? '';
      final spanEnd = spanStart + spanText.length;

      if (span.children?.isNotEmpty ?? false) {
        int childPos = currentPos;
        for (final child in span.children!) {
          if (child is TextSpan) {
            newChildren.addAll(walkAndReplace(child, childPos));
            childPos += child.toPlainText().length;
          }
        }
        return [
          TextSpan(
            style: span.style,
            children: newChildren,
            recognizer: span.recognizer,
          ),
        ];
      }

      if (spanEnd <= pathStartIndex || spanStart >= pathEndIndex) {
        return [span];
      }

      final beforeText = spanText.substring(
        0,
        (pathStartIndex - spanStart).clamp(0, spanText.length),
      );
      final linkText = spanText.substring(
        (pathStartIndex - spanStart).clamp(0, spanText.length),
        (pathEndIndex - spanStart).clamp(0, spanText.length),
      );
      final afterText = spanText.substring(
        (pathEndIndex - spanStart).clamp(0, spanText.length),
      );

      if (beforeText.isNotEmpty) {
        newChildren.add(TextSpan(text: beforeText, style: span.style));
      }
      if (linkText.isNotEmpty) {
        newChildren.add(
          TextSpan(
            text: linkText,
            style: (span.style ?? style).copyWith(
              decoration: TextDecoration.underline,
            ),
            recognizer:
                TapGestureRecognizer()..onTap = () => onImportTap(linkText),
          ),
        );
      }
      if (afterText.isNotEmpty) {
        newChildren.add(TextSpan(text: afterText, style: span.style));
      }

      return newChildren;
    }

    return TextSpan(children: walkAndReplace(textSpan, 0), style: style);
  }

  /// PIPELINE STEP 2: Finds color codes and highlights them.
  static TextSpan _highlightColorCodes(
    CodeLine codeLine,
    TextSpan textSpan,
    TextStyle style,
    void Function(ColorMatch match)? onColorCodeTap,
  ) {
    final text = codeLine.text;
    final List<ColorMatch> matches = [];

    // Regexes for color parsing
    // --- FIX START: Use negative lookbehind (?<!\w) instead of word boundary \b ---
    final hexColorRegex = RegExp(r'(?<!\w)#([A-Fa-f0-9]{8}|[A-Fa-f0-9]{6})\b');
    final shortHexColorRegex = RegExp(r'(?<!\w)#([A-Fa-f0-9]{3,4})\b');
    // --- FIX END ---
    final colorConstructorRegex = RegExp(
      r'Color\(\s*(0x[A-Fa-f0-9]{1,8})\s*\)',
    );
    final fromARGBRegex = RegExp(
      r'Color\.fromARGB\(\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*\)',
    );
    final fromRGBORegex = RegExp(
      r'Color\.fromRGBO\(\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*\)',
    );

    hexColorRegex.allMatches(text).forEach((m) {
      final hex = m.group(1);
      if (hex != null) {
        final val = int.tryParse(hex, radix: 16);
        if (val != null) {
          final color = hex.length == 8 ? Color(val) : Color(0xFF000000 | val);
          matches.add(ColorMatch(start: m.start, end: m.end, color: color, text: m.group(0)!));
        }
      }
    });
    shortHexColorRegex.allMatches(text).forEach((m) {
      String hex = m.group(1)!;
      hex =
          hex.length == 3
              ? hex.split('').map((e) => e + e).join()
              : hex[0] +
                  hex[0] +
                  hex.substring(1).split('').map((e) => e + e).join();
      final val = int.tryParse(hex, radix: 16);
      if (val != null) {
        final color = hex.length == 8 ? Color(val) : Color(0xFF000000 | val);
        matches.add(ColorMatch(start: m.start, end: m.end, color: color, text: m.group(0)!));
      }
    });
    colorConstructorRegex.allMatches(text).forEach((m) {
      final hex = m.group(1);
      if (hex != null) {
        final val = int.tryParse(hex.substring(2), radix: 16);
        if (val != null) {
          matches.add(
            ColorMatch(start: m.start, end: m.end, color: Color(val), text: m.group(0)!),
          );
        }
      }
    });
    fromARGBRegex.allMatches(text).forEach((m) {
      final a = _parseColorComponent(m.group(1));
      final r = _parseColorComponent(m.group(2));
      final g = _parseColorComponent(m.group(3));
      final b = _parseColorComponent(m.group(4));
      if (a != null && r != null && g != null && b != null) {
        matches.add(
          ColorMatch(
            start: m.start,
            end: m.end,
            color: Color.fromARGB(a, r, g, b),
            text: m.group(0)!,
          ),
        );
      }
    });
    fromRGBORegex.allMatches(text).forEach((m) {
      final r = int.tryParse(m.group(1) ?? '');
      final g = int.tryParse(m.group(2) ?? '');
      final b = int.tryParse(m.group(3) ?? '');
      final o = double.tryParse(m.group(4) ?? '');
      if (r != null && g != null && b != null && o != null) {
        matches.add(
          ColorMatch(
            start: m.start,
            end: m.end,
            color: Color.fromRGBO(r, g, b, o),
            text: m.group(0)!,
          ),
        );
      }
    });

    if (matches.isEmpty) return textSpan;
    matches.sort((a, b) => a.start.compareTo(b.start));
    final uniqueMatches = <ColorMatch>[];
    int lastEnd = -1;
    for (final match in matches) {
      if (match.start >= lastEnd) {
        uniqueMatches.add(match);
        lastEnd = match.end;
      }
    }
    if (uniqueMatches.isEmpty) return textSpan;

    List<TextSpan> walkAndColor(TextSpan span, int currentPos) {
      final newChildren = <TextSpan>[];
      final spanStart = currentPos;
      final spanText = span.text ?? '';
      final spanEnd = spanStart + spanText.length;

      if (span.children?.isNotEmpty ?? false) {
        int childPos = currentPos;
        for (final child in span.children!) {
          if (child is TextSpan) {
            newChildren.addAll(walkAndColor(child, childPos));
            childPos += child.toPlainText().length;
          }
        }
        return [
          TextSpan(
            style: span.style,
            children: newChildren,
            recognizer: span.recognizer,
          ),
        ];
      }

      int lastSplitEnd = 0;
      for (final match in uniqueMatches) {
        final int effectiveStart = max(spanStart, match.start);
        final int effectiveEnd = min(spanEnd, match.end);

        if (effectiveStart < effectiveEnd) {
          if (effectiveStart > spanStart + lastSplitEnd) {
            final beforeText = spanText.substring(
              lastSplitEnd,
              effectiveStart - spanStart,
            );
            newChildren.add(TextSpan(text: beforeText, style: span.style));
          }

          final matchText = spanText.substring(
            effectiveStart - spanStart,
            effectiveEnd - spanStart,
          );
          final isDark = match.color.computeLuminance() < 0.5;
          final textColor = isDark ? Colors.white : Colors.black;

          newChildren.add(
            TextSpan(
              text: matchText,
              style: (span.style ?? style).copyWith(
                backgroundColor: match.color,
                color: textColor,
              ),
              recognizer: onColorCodeTap == null
                  ? null
                  : (TapGestureRecognizer()..onTap = () => onColorCodeTap(match)),
            ),
          );
          lastSplitEnd = effectiveEnd - spanStart;
        }
      }

      if (lastSplitEnd < spanText.length) {
        final remainingText = spanText.substring(lastSplitEnd);
        newChildren.add(TextSpan(text: remainingText, style: span.style));
      }
      return newChildren;
    }

    return TextSpan(children: walkAndColor(textSpan, 0), style: style);
  }

  /// Helper to parse a color component from a string.
  static int? _parseColorComponent(String? s) {
    if (s == null) return null;
    s = s.trim();
    if (s.startsWith('0x')) {
      return int.tryParse(s.substring(2), radix: 16);
    }
    return int.tryParse(s);
  }

  /// PIPELINE STEP 3: Highlights matching brackets.
  static TextSpan _highlightBrackets(
    int index,
    TextSpan textSpan,
    TextStyle style,
    BracketHighlightState highlightState,
  ) {
    final highlightPositions =
        highlightState.bracketPositions
            .where((pos) => pos.index == index)
            .map((pos) => pos.offset)
            .toSet();
    if (highlightPositions.isEmpty) {
      return textSpan;
    }
    final builtSpans = <TextSpan>[];
    int currentPosition = 0;

    void processSpan(TextSpan span) {
      final text = span.text ?? '';
      final spanStyle = span.style ?? style;
      int lastSplit = 0;
      for (int i = 0; i < text.length; i++) {
        final absolutePosition = currentPosition + i;
        if (highlightPositions.contains(absolutePosition)) {
          if (i > lastSplit) {
            builtSpans.add(
              TextSpan(text: text.substring(lastSplit, i), style: spanStyle),
            );
          }
          builtSpans.add(
            TextSpan(
              text: text[i],
              style: spanStyle.copyWith(
                backgroundColor: Colors.yellow.withValues(alpha: 0.3),
                fontWeight: FontWeight.bold,
              ),
            ),
          );
          lastSplit = i + 1;
        }
      }
      if (lastSplit < text.length) {
        builtSpans.add(
          TextSpan(text: text.substring(lastSplit), style: spanStyle),
        );
      }
      currentPosition += text.length;
      if (span.children != null) {
        for (final child in span.children!) {
          if (child is TextSpan) {
            processSpan(child);
          }
        }
      }
    }

    processSpan(textSpan);
    return TextSpan(children: builtSpans, style: style);
  }

  // --- Character/Text Processing Utilities ---

  /// Finds the smallest block (e.g., (), [], {}) that fully contains the [selection].
  static ({CodeLineSelection full, CodeLineSelection contents})?
  findSmallestEnclosingBlock(
    CodeLineSelection selection,
    CodeLineEditingController controller,
  ) {
    const List<String> openDelimiters = ['(', '[', '{', '"', "'"];
    CodeLinePosition scanPos = selection.start;
    while (true) {
      final char = _getChar(scanPos, controller);
      if (char != null && openDelimiters.contains(char)) {
        final openDelimiterPos = scanPos;
        final openChar = char;
        final closeChar = _getMatchingDelimiterChar(openChar);
        final closeDelimiterPos = _findMatchingDelimiter(
          openDelimiterPos,
          openChar,
          closeChar,
          controller,
        );
        if (closeDelimiterPos != null) {
          final fullBlockSelection = CodeLineSelection(
            baseIndex: openDelimiterPos.index,
            baseOffset: openDelimiterPos.offset,
            extentIndex: closeDelimiterPos.index,
            extentOffset: closeDelimiterPos.offset + 1,
          );
          if (fullBlockSelection.contains(selection)) {
            final contentSelection = CodeLineSelection(
              baseIndex: openDelimiterPos.index,
              baseOffset: openDelimiterPos.offset + 1,
              extentIndex: closeDelimiterPos.index,
              extentOffset: closeDelimiterPos.offset,
            );
            return (full: fullBlockSelection, contents: contentSelection);
          }
        }
      }
      final prevPos = _getPreviousPosition(scanPos, controller);
      if (prevPos == scanPos) {
        break;
      }
      scanPos = prevPos;
    }
    return null;
  }

  /// Finds the position of a matching closing delimiter, respecting nested pairs.
  static CodeLinePosition? _findMatchingDelimiter(
    CodeLinePosition start,
    String open,
    String close,
    CodeLineEditingController controller,
  ) {
    int stack = 1;
    CodeLinePosition currentPos = _getNextPosition(start, controller);
    while (true) {
      final char = _getChar(currentPos, controller);
      if (char != null) {
        if (char == open && open != close) {
          stack++;
        } else if (char == close) {
          stack--;
        }
        if (stack == 0) {
          return currentPos;
        }
      }
      final nextPos = _getNextPosition(currentPos, controller);
      if (nextPos == currentPos) {
        break;
      }
      currentPos = nextPos;
    }
    return null;
  }

  /// Given an opening delimiter, returns its closing counterpart.
  static String _getMatchingDelimiterChar(String openChar) {
    const Map<String, String> pairs = {
      '(': ')',
      '[': ']',
      '{': '}',
      '"': '"',
      "'": "'",
    };
    return pairs[openChar]!;
  }

  /// Gets the character at a given position, returning null on failure.
  static String? _getChar(
    CodeLinePosition pos,
    CodeLineEditingController controller,
  ) {
    if (pos.index < 0 || pos.index >= controller.codeLines.length) return null;
    final line = controller.codeLines[pos.index].text;
    if (pos.offset < 0 || pos.offset >= line.length) return null;
    return line[pos.offset];
  }

  /// Gets the character position immediately before the given one.
  static CodeLinePosition _getPreviousPosition(
    CodeLinePosition pos,
    CodeLineEditingController controller,
  ) {
    if (pos.offset > 0) {
      return CodeLinePosition(index: pos.index, offset: pos.offset - 1);
    }
    if (pos.index > 0) {
      final prevLine = controller.codeLines[pos.index - 1].text;
      return CodeLinePosition(index: pos.index - 1, offset: prevLine.length);
    }
    return pos;
  }

  /// Gets the character position immediately after the given one.
  static CodeLinePosition _getNextPosition(
    CodeLinePosition pos,
    CodeLineEditingController controller,
  ) {
    final line = controller.codeLines[pos.index].text;
    if (pos.offset < line.length) {
      return CodeLinePosition(index: pos.index, offset: pos.offset + 1);
    }
    if (pos.index < controller.codeLines.length - 1) {
      return CodeLinePosition(index: pos.index + 1, offset: 0);
    }
    return pos;
  }

  /// Compares two CodeLinePositions.
  static int comparePositions(CodeLinePosition a, CodeLinePosition b) {
    if (a.index < b.index) return -1;
    if (a.index > b.index) return 1;
    return a.offset.compareTo(b.offset);
  }
}
