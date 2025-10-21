// MODIFIED FILE: lib/editor/plugins/llm_editor/code_block_controller.dart

import 'dart:async';
import 'package.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/llm_editor/llm_highlight_util.dart';
import 'package:re_highlight/re_highlight.dart';

// --- DATA STRUCTURES FOR ISOLATE COMMUNICATION ---

// Represents a single styled piece of text
class _HighlightNode {
  final String? className;
  final String value;
  const _HighlightNode(this.value, [this.className]);
}

// The result for a single line of code
class _HighlightLineResult {
  final List<_HighlightNode> nodes;
  const _HighlightLineResult(this.nodes);
}

// Payload for the partial highlighting isolate
class _PartialHighlightPayload {
  final List<String> codeLines;
  final int dirtyLineIndex;
  final String language;

  const _PartialHighlightPayload({
    required this.codeLines,
    required this.dirtyLineIndex,
    required this.language,
  });
}

// Renders HighlightResult into a list of line results
class _HighlightLineRenderer implements HighlightRenderer {
  final List<_HighlightLineResult> lineResults;
  final List<String?> classNames;
  _HighlightLineRenderer()
      : lineResults = [_HighlightLineResult([])],
        classNames = [];

  @override
  void addText(String text) {
    final String? className = classNames.isEmpty ? null : classNames.last;
    final List<String> lines = text.split('\n');
    lineResults.last.nodes.add(_HighlightNode(lines.first, className));
    if (lines.length > 1) {
      for (int i = 1; i < lines.length; i++) {
        lineResults.add(_HighlightLineResult([_HighlightNode(lines[i], className)]));
      }
    }
  }

  @override
  void openNode(DataNode node) {
    final String? className = classNames.isEmpty ? null : classNames.last;
    String? newClassName;
    if (className == null || node.scope == null) {
      newClassName = node.scope;
    } else {
      newClassName = '$className-${node.scope!}';
    }
    newClassName = newClassName?.split('.')[0];
    classNames.add(newClassName);
  }

  @override
  void closeNode(DataNode node) {
    if (classNames.isNotEmpty) {
      classNames.removeLast();
    }
  }
}

// --- TOP-LEVEL ISOLATE FUNCTION ---

Map<int, _HighlightLineResult> _highlightPartialIsolate(_PartialHighlightPayload payload) {
  const int contextSize = 20; // smaller context for faster partial updates
  final int startLine = max(0, payload.dirtyLineIndex - contextSize);
  final int endLine = min(payload.codeLines.length, payload.dirtyLineIndex + contextSize + 1);

  if (startLine >= endLine) {
    return {};
  }

  final linesToHighlight = payload.codeLines.sublist(startLine, endLine);
  final textChunk = linesToHighlight.join('\n');
  
  LlmHighlightUtil.ensureLanguagesRegistered();
  final HighlightResult result = LlmHighlightUtil.highlight.highlight(code: textChunk, language: payload.language);
  
  final renderer = _HighlightLineRenderer();
  result.render(renderer);
  
  final Map<int, _HighlightLineResult> updatedResults = {};
  for (int i = 0; i < renderer.lineResults.length; i++) {
    final int absoluteLineIndex = startLine + i;
    if (absoluteLineIndex < payload.codeLines.length) {
      updatedResults[absoluteLineIndex] = renderer.lineResults[i];
    }
  }
  
  return updatedResults;
}

// --- THE CONTROLLER ---

class CodeBlockController extends ChangeNotifier {
  final TextStyle textStyle;
  final Map<String, TextStyle> theme;
  final String language;

  List<String> _codeLines = [];
  List<TextSpan> _highlightedLines = [];

  bool _isFolded = false;
  Timer? _debounceTimer;

  // The final composite TextSpan that the UI displays.
  TextSpan get displaySpan => TextSpan(
    style: textStyle,
    children: _intersperse(const TextSpan(text: '\n'), _highlightedLines).toList(),
  );

  bool get isFolded => _isFolded;

  CodeBlockController({
    required String initialCode,
    required this.language,
    required this.textStyle,
    required this.theme,
  }) {
    updateCode(initialCode, initial: true);
  }
  
  void toggleFold() {
    _isFolded = !_isFolded;
    notifyListeners();
  }

  void updateCode(String newCode, {bool initial = false}) {
    final newLines = newCode.split('\n');
    final oldLinesCount = _codeLines.length;
    final newLinesCount = newLines.length;

    // Immediately update the UI with plain text for new/changed lines
    if (newLinesCount > oldLinesCount) {
      _highlightedLines.addAll(newLines.sublist(oldLinesCount).map((line) => TextSpan(text: line)));
    } else if (newLinesCount < oldLinesCount) {
      _highlightedLines.removeRange(newLinesCount, oldLinesCount);
    }

    if (newLinesCount > 0 && (oldLinesCount == 0 || newLines.last != _codeLines.last)) {
       _highlightedLines[newLinesCount - 1] = TextSpan(text: newLines.last);
    }
    
    _codeLines = newLines;

    if (!initial) {
      // Show un-styled text immediately for responsiveness
      notifyListeners(); 
    }
    
    // Debounce the expensive partial highlighting
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _runPartialHighlight();
    });
  }

  Future<void> _runPartialHighlight() async {
    if (_codeLines.isEmpty) return;

    final payload = _PartialHighlightPayload(
      codeLines: _codeLines,
      dirtyLineIndex: _codeLines.length - 1, // We only append, so dirty line is the last
      language: language,
    );

    try {
      final Map<int, _HighlightLineResult> result = await compute(_highlightPartialIsolate, payload);

      for (final entry in result.entries) {
        final lineIndex = entry.key;
        if (lineIndex < _highlightedLines.length) {
          _highlightedLines[lineIndex] = _renderNodesToSpan(entry.value.nodes);
        }
      }
    } catch (e) {
      // Don't crash, just log it. The UI will show plain text.
      debugPrint("Partial highlighting failed: $e");
    } finally {
      notifyListeners();
    }
  }

  TextSpan _renderNodesToSpan(List<_HighlightNode> nodes) {
    if (nodes.isEmpty) return const TextSpan(text: '');
    return TextSpan(
      children: nodes.map((e) => TextSpan(
        text: e.value,
        style: _findStyle(e.className),
      )).toList(),
    );
  }

  // Helper to find styles in the theme map
  TextStyle? _findStyle(String? className) {
    if (className == null) return null;
    return theme[className]; // Simplified lookup
  }
  
  // Helper to join TextSpans with a separator
  Iterable<T> _intersperse<T>(T separator, Iterable<T> elements) {
    if (elements.isEmpty) return [];
    final iterator = elements.iterator;
    iterator.moveNext();
    var result = <T>[iterator.current];
    while (iterator.moveNext()) {
      result.add(separator);
      result.add(iterator.current);
    }
    return result;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}