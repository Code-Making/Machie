// =========================================
// UPDATED: lib/editor/plugins/code_editor/logic/code_editor_utils.dart
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
    // NEW PARAMETER for analysis results
    void Function(String filePath, int lineNumber, int columnNumber)? onAnalysisResultTap,
  }) {
    List<TextSpan> currentSpans = [textSpan]; // Start with the initial textSpan

    // Pipeline Step 1: Add tappable links to import paths.
    currentSpans = _linkifyImportPaths(
      codeLine,
      currentSpans, // Pass list of spans
      style,
      onImportTap,
      languageConfig,
    );

    // Pipeline Step 2: Highlight color codes
    currentSpans = _highlightColorCodes(
      codeLine,
      currentSpans, // Pass list of spans
      style,
      onColorCodeTap != null ? (match) => onColorCodeTap(index, match) : null,
    );

    // Pipeline Step 3: Highlight matching brackets
    currentSpans = _highlightBrackets(
      index,
      currentSpans, // Pass list of spans
      style,
      bracketHighlightState,
    );

    // NEW PIPELINE STEP 4: Add tappable links for analysis results (if callback is provided)
    if (onAnalysisResultTap != null) {
      currentSpans = _linkifyAnalysisResults(
        codeLine,
        currentSpans, // Pass list of spans
        style,
        onAnalysisResultTap,
      );
    }

    // Combine all spans into a single TextSpan for the editor
    return TextSpan(children: currentSpans, style: style);
  }

  /// A generic helper to apply a regex-based transformation to a list of TextSpans.
  /// It iterates through the spans, finds matches, splits/replaces text, and builds new spans.
  static List<TextSpan> _processSpansWithRegex({
    required List<TextSpan> initialSpans,
    required String fullLineText,
    required RegExp regex,
    required TextStyle defaultStyle,
    required TextSpan Function(Match match, TextStyle baseStyle, GestureRecognizer? baseRecognizer) matchSpanBuilder,
  }) {
    final List<TextSpan> resultSpans = [];
    int currentGlobalOffset = 0; // Tracks position in the fullLineText

    for (final TextSpan span in initialSpans) {
      final String spanText = span.text ?? '';
      final TextStyle spanStyle = span.style ?? defaultStyle;
      final GestureRecognizer? spanRecognizer = span.recognizer;

      int lastProcessedOffsetInSpan = 0;

      // Find all matches that potentially overlap with the current span
      for (final Match match in regex.allMatches(fullLineText)) {
        final int matchGlobalStart = match.start;
        final int matchGlobalEnd = match.end;

        // Calculate intersection with current span
        final int intersectionStart = max(currentGlobalOffset, matchGlobalStart);
        final int intersectionEnd = min(currentGlobalOffset + spanText.length, matchGlobalEnd);

        if (intersectionStart < intersectionEnd) {
          // Add text *before* the match within the current span
          final int textBeforeMatchInSpanStart = currentGlobalOffset + lastProcessedOffsetInSpan;
          if (intersectionStart > textBeforeMatchInSpanStart) {
            resultSpans.add(
              TextSpan(
                text: fullLineText.substring(textBeforeMatchInSpanStart, intersectionStart),
                style: spanStyle,
                recognizer: spanRecognizer,
              ),
            );
          }

          // Add the matched text with custom styling
          resultSpans.add(
            matchSpanBuilder(match, spanStyle, spanRecognizer).copyWith(
              text: fullLineText.substring(intersectionStart, intersectionEnd),
            ),
          );

          lastProcessedOffsetInSpan = intersectionEnd - currentGlobalOffset;
        }
      }

      // Add any remaining text *after* the last match within the current span
      if (lastProcessedOffsetInSpan < spanText.length) {
        resultSpans.add(
          TextSpan(
            text: spanText.substring(lastProcessedOffsetInSpan),
            style: spanStyle,
            recognizer: spanRecognizer,
          ),
        );
      }
      currentGlobalOffset += spanText.length;
    }
    return resultSpans;
  }

  /// PIPELINE STEP 1: Finds import paths and makes them tappable.
  static List<TextSpan> _linkifyImportPaths(
    CodeLine codeLine,
    List<TextSpan> initialSpans,
    TextStyle style,
    void Function(String) onImportTap,
    LanguageConfig config,
  ) {
    final text = codeLine.text;
    if (!(text.startsWith('import') || text.startsWith('export') || text.startsWith('part'))) {
      return initialSpans;
    }
    // Filter out package: and dart: imports as they're not local files.
    if (text.contains(':')) return initialSpans;

    // This regex matches only the quoted path string and captures its content.
    // Group 1 for single quotes, Group 2 for double quotes. One will be null.
    final RegExp importPathRegex = RegExp(r"(?:'([^']+)'|\"([^\"]+)\")");

    return _processSpansWithRegex(
      initialSpans: initialSpans,
      fullLineText: text,
      regex: importPathRegex,
      defaultStyle: style,
      matchSpanBuilder: (match, baseStyle, baseRecognizer) {
        final String path = match.group(1) ?? match.group(2)!; // Get the captured path content
        return TextSpan(
          style: baseStyle.copyWith(decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()..onTap = () => onImportTap(path),
        );
      },
    );
  }

  /// PIPELINE STEP 2: Finds color codes and highlights them.
  static List<TextSpan> _highlightColorCodes(
    CodeLine codeLine,
    List<TextSpan> initialSpans,
    TextStyle style,
    void Function(ColorMatch match)? onColorCodeTap,
  ) {
    final text = codeLine.text;

    // Combined regex for all supported color formats
    final RegExp combinedColorRegex = RegExp(
      r'(?<!\w)#([A-Fa-f0-9]{3,4}|[A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})\b|'
      r'Color\(\s*(0x[A-Fa-f0-9]{1,8})\s*\)|'
      r'Color\.fromARGB\(\s*[^,]+?\s*,\s*[^,]+?\s*,\s*[^,]+?\s*,\s*[^,]+?\s*\)|'
      r'Color\.fromRGBO\(\s*[^,]+?\s*,\s*[^,]+?\s*,\s*[^,]+?\s*,\s*[^,]+?\s*\)',
    );

    return _processSpansWithRegex(
      initialSpans: initialSpans,
      fullLineText: text,
      regex: combinedColorRegex,
      defaultStyle: style,
      matchSpanBuilder: (match, baseStyle, baseRecognizer) {
        final ColorMatch? colorMatch = _parseSingleColorMatch(match);

        if (colorMatch != null) {
          final bool isDark = colorMatch.color.computeLuminance() < 0.5;
          final Color textColor = isDark ? Colors.white : Colors.black;
          return TextSpan(
            style: baseStyle.copyWith(
              backgroundColor: colorMatch.color,
              color: textColor,
            ),
            recognizer: onColorCodeTap == null
                ? baseRecognizer
                : (TapGestureRecognizer()..onTap = () => onColorCodeTap(colorMatch)),
          );
        }
        return TextSpan(style: baseStyle, recognizer: baseRecognizer);
      },
    );
  }

  /// Helper to parse a single color match from a regex match object.
  static ColorMatch? _parseSingleColorMatch(Match m) {
    final String matchedText = m.group(0)!;
    final int start = m.start;
    final int end = m.end;

    // Hex color parsing (e.g., #RRGGBB, #RGB, #AARRGGBB, #RGBA)
    Match? hexMatch = RegExp(r'#([A-Fa-f0-9]+)').firstMatch(matchedText);
    if (hexMatch != null) {
      String hex = hexMatch.group(1)!;
      if (hex.length == 3) hex = hex.split('').map((e) => e + e).join(); // #RGB to #RRGGBB
      if (hex.length == 4) hex = hex[0] + hex[0] + hex.substring(1).split('').map((e) => e + e).join(); // #RGBA to #AARRGGBB
      final val = int.tryParse(hex, radix: 16);
      if (val != null) {
        final color = (hex.length == 6 || hex.length == 3) ? Color(0xFF000000 | val) : Color(val);
        return ColorMatch(start: start, end: end, color: color, text: matchedText);
      }
    }

    // Color(0x...) constructor parsing
    Match? constructorMatch = RegExp(r'Color\(\s*(0x[A-Fa-f0-9]{1,8})\s*\)').firstMatch(matchedText);
    if (constructorMatch != null) {
      final hex = constructorMatch.group(1);
      if (hex != null) {
        final val = int.tryParse(hex.substring(2), radix: 16);
        if (val != null) {
          return ColorMatch(start: start, end: end, color: Color(val), text: matchedText);
        }
      }
    }

    // Color.fromARGB(...) constructor parsing
    Match? argbMatch = RegExp(r'Color\.fromARGB\(\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*\)').firstMatch(matchedText);
    if (argbMatch != null) {
      final a = _parseColorComponent(argbMatch.group(1));
      final r = _parseColorComponent(argbMatch.group(2));
      final g = _parseColorComponent(argbMatch.group(3));
      final b = _parseColorComponent(argbMatch.group(4));
      if (a != null && r != null && g != null && b != null) {
        return ColorMatch(start: start, end: end, color: Color.fromARGB(a, r, g, b), text: matchedText);
      }
    }

    // Color.fromRGBO(...) constructor parsing
    Match? rgbaMatch = RegExp(r'Color\.fromRGBO\(\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*\)').firstMatch(matchedText);
    if (rgbaMatch != null) {
      final r = int.tryParse(rgbaMatch.group(1) ?? '');
      final g = int.tryParse(rgbaMatch.group(2) ?? '');
      final b = int.tryParse(rgbaMatch.group(3) ?? '');
      final o = double.tryParse(rgbaMatch.group(4) ?? '');
      if (r != null && g != null && b != null && o != null) {
        return ColorMatch(start: start, end: end, color: Color.fromRGBO(r, g, b, o), text: matchedText);
      }
    }

    return null;
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
  static List<TextSpan> _highlightBrackets(
    int index,
    List<TextSpan> initialSpans,
    TextStyle style,
    BracketHighlightState highlightState,
  ) {
    final highlightPositions =
        highlightState.bracketPositions
            .where((pos) => pos.index == index)
            .map((pos) => pos.offset)
            .toSet();
    if (highlightPositions.isEmpty) {
      return initialSpans;
    }

    final List<TextSpan> resultSpans = [];
    int currentGlobalOffset = 0;

    for (final TextSpan span in initialSpans) {
      final String spanText = span.text ?? '';
      final TextStyle spanStyle = span.style ?? style;
      final GestureRecognizer? spanRecognizer = span.recognizer;

      int lastSplit = 0;
      for (int i = 0; i < spanText.length; i++) {
        final absolutePosition = currentGlobalOffset + i;
        if (highlightPositions.contains(absolutePosition)) {
          if (i > lastSplit) {
            resultSpans.add(
              TextSpan(text: spanText.substring(lastSplit, i), style: spanStyle, recognizer: spanRecognizer),
            );
          }
          resultSpans.add(
            TextSpan(
              text: spanText[i],
              style: spanStyle.copyWith(
                backgroundColor: Colors.yellow.withOpacity(0.3),
                fontWeight: FontWeight.bold,
              ),
              recognizer: spanRecognizer,
            ),
          );
          lastSplit = i + 1;
        }
      }
      if (lastSplit < spanText.length) {
        resultSpans.add(
          TextSpan(text: spanText.substring(lastSplit), style: spanStyle, recognizer: spanRecognizer),
        );
      }
      currentGlobalOffset += spanText.length;
    }
    return resultSpans;
  }

  /// NEW PIPELINE STEP 4: Finds Dart analysis results (error, warning, info) and makes the path tappable.
  static List<TextSpan> _linkifyAnalysisResults(
    CodeLine codeLine,
    List<TextSpan> initialSpans,
    TextStyle style,
    void Function(String filePath, int lineNumber, int columnNumber) onAnalysisResultTap,
  ) {
    final text = codeLine.text;
    // Regex to capture file path, line, and column from analysis output
    // Example: `error - lib/path/to/file.dart:123:45 - Message`
    final RegExp analysisResultRegex = RegExp(
      r'(error|warning|info)\s*-\s*([a-zA-Z0-9_/.-]+\.dart):(\d+):(\d+)\s*-\s*',
    );

    return _processSpansWithRegex(
      initialSpans: initialSpans,
      fullLineText: text,
      regex: analysisResultRegex,
      defaultStyle: style,
      matchSpanBuilder: (match, baseStyle, baseRecognizer) {
        // The regex matches the entire `error - path:line:col - ` part.
        // We want to make the `path:line:col` part clickable.
        // Group 2 is the file path.
        // Group 3 is the line number.
        // Group 4 is the column number.
        final String filePath = match.group(2)!;
        final int lineNumber = int.parse(match.group(3)!);
        final int columnNumber = int.parse(match.group(4)!);

        // Find the start and end of the `path:line:col` part within the overall match.
        final int pathStartInMatch = matchedText.indexOf(filePath);
        final int pathEndInMatch = matchedText.indexOf(':', pathStartInMatch + filePath.length) +
            match.group(3)!.length +
            1 + // for ':'
            match.group(4)!.length; // for column

        // Extract parts for styling
        final String beforePath = matchedText.substring(0, pathStartInMatch);
        final String pathPart = matchedText.substring(pathStartInMatch, pathEndInMatch);
        final String afterPath = matchedText.substring(pathEndInMatch);

        return TextSpan(
          style: baseStyle,
          recognizer: baseRecognizer,
          children: [
            TextSpan(text: beforePath, style: baseStyle, recognizer: baseRecognizer),
            TextSpan(
              text: pathPart,
              style: baseStyle.copyWith(
                decoration: TextDecoration.underline,
                color: Colors.blue, // Make it look like a link
              ),
              recognizer: TapGestureRecognizer()..onTap = () {
                onAnalysisResultTap(filePath, lineNumber, columnNumber);
              },
            ),
            TextSpan(text: afterPath, style: baseStyle, recognizer: baseRecognizer),
          ],
        );
      },
    );
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