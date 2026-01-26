// lib/editor/plugins/code_editor/logic/code_editor_utils.dart

import 'dart:math';
import 'dart:ui'; // For Color

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'code_editor_types.dart';
import '../../../services/language/language_models.dart';
import '../../../services/language/parsed_span_models.dart';

class CodeEditorUtils {
  
  // --- Bracket Matching Logic (Unchanged) ---
  
  static BracketHighlightState calculateBracketHighlights(
    CodeLineEditingController controller,
  ) {
    // ... [Previous implementation of calculateBracketHighlights matches here] ...
    // (Kept separate as it depends on cursor position, not just line content)
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

  static CodeLinePosition? _findMatchingBracket(
    CodeLines codeLines,
    CodeLinePosition position,
    Map<String, String> brackets,
  ) {
    // ... [Previous implementation] ...
    final line = codeLines[position.index].text;
    final char = line[position.offset];
    final isOpen = brackets.keys.contains(char);
    final target = isOpen
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

  // --- Unified Highlight Span Builder Pipeline ---

  /// The main entry point for building the enhanced TextSpan for a line.
  /// 
  /// Changes:
  /// 1. Uses [languageConfig.parser] to find all decorations (links, colors).
  /// 2. Uses generic [_applyParsedSpans] to render them.
  static TextSpan buildHighlightingSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
    required BracketHighlightState bracketHighlightState,
    required void Function(LinkSpan) onLinkTap, // Updated Signature
    void Function(int lineIndex, ColorSpan span)? onColorTap, // Updated Signature
    required LanguageConfig languageConfig,
  }) {
    // 1. Get raw data from the language parser
    final parsedSpans = languageConfig.parser(codeLine.text);

    // 2. Apply all semantic decorations (Links, Colors) in one pass
    final decoratedSpan = _applyParsedSpans(
      textSpan,
      parsedSpans,
      style,
      onLinkTap: onLinkTap,
      onColorTap: onColorTap != null ? (span) => onColorTap(index, span) : null,
    );

    // 3. Highlight matching brackets (Overlay logic)
    final finalSpan = _highlightBrackets(
      index,
      decoratedSpan,
      style,
      bracketHighlightState,
    );

    return finalSpan;
  }

  /// The Core Rendering Engine.
  /// Walks the TextSpan tree and applies styles/recognizers defined by [spans].
  static TextSpan _applyParsedSpans(
    TextSpan originalSpan,
    List<ParsedSpan> spans,
    TextStyle defaultStyle, {
    required void Function(LinkSpan)? onLinkTap,
    required void Function(ColorSpan)? onColorTap,
  }) {
    if (spans.isEmpty) return originalSpan;

    // Sort spans to ensure we process them in order. 
    // Note: Overlapping spans are not currently supported by this simple walker 
    // (the first one encountered wins or they might nest oddly).
    // Parsers should ideally return non-overlapping spans.
    spans.sort((a, b) => a.start.compareTo(b.start));

    // Flatten to unique ranges if necessary, but assuming clean input for now.
    
    List<TextSpan> walk(TextSpan span, int currentPos) {
      final newChildren = <TextSpan>[];
      final spanStart = currentPos;
      final spanText = span.text ?? '';
      final spanEnd = spanStart + spanText.length;

      // 1. If this span has children, recurse down.
      if (span.children?.isNotEmpty ?? false) {
        int childPos = currentPos;
        for (final child in span.children!) {
          if (child is TextSpan) {
            newChildren.addAll(walk(child, childPos));
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

      // 2. Leaf Node Processing
      int lastSplitEnd = 0; // Relative to spanText start

      // Find spans that intersect with this leaf node
      for (final parsedSpan in spans) {
        final int effectiveStart = max(spanStart, parsedSpan.start);
        final int effectiveEnd = min(spanEnd, parsedSpan.end);

        // Check intersection
        if (effectiveStart < effectiveEnd) {
          // A. Add text *before* the match (if any)
          if (effectiveStart > spanStart + lastSplitEnd) {
            final beforeText = spanText.substring(
              lastSplitEnd,
              effectiveStart - spanStart,
            );
            newChildren.add(TextSpan(text: beforeText, style: span.style));
          }

          // B. Add the *matched* text with decoration
          final matchText = spanText.substring(
            effectiveStart - spanStart,
            effectiveEnd - spanStart,
          );

          newChildren.add(
            _createStyledSpan(
              text: matchText,
              baseStyle: span.style ?? defaultStyle,
              parsedSpan: parsedSpan,
              onLinkTap: onLinkTap,
              onColorTap: onColorTap,
            ),
          );

          lastSplitEnd = effectiveEnd - spanStart;
        }
      }

      // C. Add remaining text *after* the last match
      if (lastSplitEnd < spanText.length) {
        final remainingText = spanText.substring(lastSplitEnd);
        newChildren.add(TextSpan(text: remainingText, style: span.style));
      }

      return newChildren;
    }

    return TextSpan(children: walk(originalSpan, 0), style: defaultStyle);
  }

  /// Helper to generate the specific TextSpan for a Link or Color.
  static TextSpan _createStyledSpan({
    required String text,
    required TextStyle baseStyle,
    required ParsedSpan parsedSpan,
    required void Function(LinkSpan)? onLinkTap,
    required void Function(ColorSpan)? onColorTap,
  }) {
    switch (parsedSpan) {
      case LinkSpan():
        return TextSpan(
          text: text,
          style: baseStyle.copyWith(
            decoration: TextDecoration.underline,
            //color: Colors.blueAccent, // Or theme primary color
          ),
          recognizer: onLinkTap == null 
              ? null 
              : (TapGestureRecognizer()..onTap = () => onLinkTap(parsedSpan)),
        );

      case ColorSpan():
        // Calculate contrast color for text
        final isDark = parsedSpan.color.computeLuminance() < 0.5;
        final textColor = isDark ? Colors.white : Colors.black;
        
        return TextSpan(
          text: text,
          style: baseStyle.copyWith(
            backgroundColor: parsedSpan.color,
            color: textColor,
          ),
          recognizer: onColorTap == null
              ? null
              : (TapGestureRecognizer()..onTap = () => onColorTap(parsedSpan)),
        );
    }
  }

  // --- PIPELINE STEP 3: Highlights matching brackets (Unchanged) ---
  static TextSpan _highlightBrackets(
    int index,
    TextSpan textSpan,
    TextStyle style,
    BracketHighlightState highlightState,
  ) {
    // ... [Previous logic stays exactly the same] ...
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

  // --- Character/Text Processing Utilities (Unchanged) ---
  // ... [findSmallestEnclosingBlock, etc. remain as is] ...
  
  static ({CodeLineSelection full, CodeLineSelection contents})?
  findSmallestEnclosingBlock(
    CodeLineSelection selection,
    CodeLineEditingController controller,
  ) {
     // ... (Implementation from previous code)
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

  static String? _getChar(
    CodeLinePosition pos,
    CodeLineEditingController controller,
  ) {
    if (pos.index < 0 || pos.index >= controller.codeLines.length) return null;
    final line = controller.codeLines[pos.index].text;
    if (pos.offset < 0 || pos.offset >= line.length) return null;
    return line[pos.offset];
  }

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

  static int comparePositions(CodeLinePosition a, CodeLinePosition b) {
    if (a.index < b.index) return -1;
    if (a.index > b.index) return 1;
    return a.offset.compareTo(b.offset);
  }
}