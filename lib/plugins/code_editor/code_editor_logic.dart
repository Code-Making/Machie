// lib/plugins/code_editor/code_editor_logic.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../app/app_notifier.dart';
import 'code_editor_models.dart';
import 'code_editor_plugin.dart';

// --- Logic Class ---

class CodeEditorLogic {
  static CodeCommentFormatter getCommentFormatter(String uri) {
    final extension = uri.split('.').last.toLowerCase();
    switch (extension) {
      case 'dart':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
      case 'tex':
        return DefaultCodeCommentFormatter(singleLinePrefix: '%');
      default:
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
    }
  }
}

// --- Bracket Highlighting State ---

final bracketHighlightProvider =
    NotifierProvider<BracketHighlightNotifier, BracketHighlightState>(
      BracketHighlightNotifier.new,
    );

class BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final CodeLinePosition? matchingBracketPosition;
  final Set<int> highlightedLines;
  BracketHighlightState({
    this.bracketPositions = const {},
    this.matchingBracketPosition,
    this.highlightedLines = const {},
  });
}

class BracketHighlightNotifier extends Notifier<BracketHighlightState> {
  @override
  BracketHighlightState build() {
    return BracketHighlightState();
  }

  void handleBracketHighlight() {
    final currentTab =
        ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (currentTab is! CodeEditorTab) {
      state = BracketHighlightState();
      return;
    }

    final plugin = currentTab.plugin as CodeEditorPlugin;
    final controller = plugin.getControllerForTab(currentTab);

    if (controller == null) {
      state = BracketHighlightState();
      return;
    }

    final selection = controller.selection;
    if (!selection.isCollapsed) {
      state = BracketHighlightState();
      return;
    }
    final position = selection.base;
    final brackets = {'(': ')', '[': ']', '{': '}'};
    final line = controller.codeLines[position.index].text;

    Set<CodeLinePosition> newPositions = {};
    CodeLinePosition? matchPosition;
    Set<int> newHighlightedLines = {};

    final index = position.offset;
    if (index >= 0 && index < line.length) {
      final char = line[index];
      if (brackets.keys.contains(char) || brackets.values.contains(char)) {
        matchPosition = _findMatchingBracket(
          controller.codeLines,
          position,
          brackets,
        );
        if (matchPosition != null) {
          newPositions.add(position);
          newPositions.add(matchPosition);
          newHighlightedLines.add(position.index);
          newHighlightedLines.add(matchPosition.index);
        }
      }
    }

    state = BracketHighlightState(
      bracketPositions: newPositions,
      matchingBracketPosition: matchPosition,
      highlightedLines: newHighlightedLines,
    );
  }

  CodeLinePosition? _findMatchingBracket(
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

    while (index >= 0 && index < codeLines.length) {
      final currentLine = codeLines[index].text;

      while (offset >= 0 && offset < currentLine.length) {
        if (index == position.index && offset == position.offset) {
          offset += direction;
          continue;
        }

        final currentChar = currentLine[offset];

        if (currentChar == char) {
          stack += 1;
        } else if (currentChar == target) {
          stack -= 1;
        }

        if (stack == 0) {
          return CodeLinePosition(index: index, offset: offset);
        }

        offset += direction;
      }

      index += direction;
      offset = direction > 0 ? 0 : (codeLines[index].text.length - 1);
    }
    return null;
  }
}

// --- Highlighting Span Builder ---

TextSpan buildHighlightingSpan({
  required BuildContext context,
  required int index,
  required CodeLine codeLine,
  required TextSpan textSpan,
  required TextStyle style,
}) {
  final highlightState = ProviderScope.containerOf(
    context,
  ).read(bracketHighlightProvider);

  final spans = <TextSpan>[];
  int currentPosition = 0;
  final highlightPositions =
      highlightState.bracketPositions
          .where((pos) => pos.index == index)
          .map((pos) => pos.offset)
          .toSet();
  void processSpan(TextSpan span) {
    final text = span.text ?? '';
    final spanStyle = span.style ?? style;
    List<int> highlightIndices = [];

    for (var i = 0; i < text.length; i++) {
      if (highlightPositions.contains(currentPosition + i)) {
        highlightIndices.add(i);
      }
    }

    int lastSplit = 0;
    for (final highlightIndex in highlightIndices) {
      if (highlightIndex > lastSplit) {
        spans.add(
          TextSpan(
            text: text.substring(lastSplit, highlightIndex),
            style: spanStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: text[highlightIndex],
          style: spanStyle.copyWith(
            backgroundColor: Colors.yellow.withOpacity(0.3),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      lastSplit = highlightIndex + 1;
    }

    if (lastSplit < text.length) {
      spans.add(TextSpan(text: text.substring(lastSplit), style: spanStyle));
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
  return TextSpan(
    children: spans.isNotEmpty ? spans : [textSpan],
    style: style,
  );
}
