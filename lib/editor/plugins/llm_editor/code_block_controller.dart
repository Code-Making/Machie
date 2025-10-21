// FINAL CORRECTED FILE: lib/editor/plugins/llm_editor/code_block_controller.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/llm_editor/llm_highlight_util.dart';
import 'package:re_highlight/re_highlight.dart';

// --- DATA STRUCTURES and ISOLATE FUNCTION are UNCHANGED ---

class _HighlightNode {
  final String? className;
  final String value;
  const _HighlightNode(this.value, [this.className]);
}

class _HighlightLineResult {
  final List<_HighlightNode> nodes;
  const _HighlightLineResult(this.nodes);
}

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

class _HighlightLineRenderer implements HighlightRenderer {
    // ... implementation unchanged ...
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
    if (className == null || node.scope == null) { newClassName = node.scope; } else { newClassName = '$className-${node.scope!}'; }
    newClassName = newClassName?.split('.')[0];
    classNames.add(newClassName);
  }
  @override
  void closeNode(DataNode node) {
    if (classNames.isNotEmpty) { classNames.removeLast(); }
  }
}

Map<int, _HighlightLineResult> _highlightPartialIsolate(_PartialHighlightPayload payload) {
    // ... implementation unchanged ...
  const int contextSize = 20;
  final int startLine = max(0, payload.dirtyLineIndex - contextSize);
  final int endLine = min(payload.codeLines.length, payload.dirtyLineIndex + contextSize + 1);
  if (startLine >= endLine) { return {}; }
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

// --- THE CONTROLLER (with corrected logic) ---

class CodeBlockController extends ChangeNotifier {
  final TextStyle textStyle;
  final Map<String, TextStyle> theme;
  final String language;

  List<String> _codeLines = [];
  List<TextSpan> _highlightedLines = [];

  bool _isFolded = false;
  Timer? _debounceTimer;

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

  // *** REWRITTEN UPDATE LOGIC ***
  void updateCode(String newCode, {bool initial = false}) {
    final newLines = newCode.split('\n');
    final newHighlightedLines = <TextSpan>[];
    int firstDirtyLine = -1;
    bool needsNotify = false;

    // Build the new list of TextSpans, intelligently reusing old ones.
    for (int i = 0; i < newLines.length; i++) {
      if (i < _codeLines.length && newLines[i] == _codeLines[i]) {
        // Line is UNCHANGED. Reuse the already highlighted TextSpan.
        newHighlightedLines.add(_highlightedLines[i]);
      } else {
        // Line is NEW or CHANGED. Use plain text for now.
        newHighlightedLines.add(TextSpan(text: newLines[i]));
        needsNotify = true;
        if (firstDirtyLine == -1) {
          firstDirtyLine = i;
        }
      }
    }

    if (newLines.length != _codeLines.length) {
        needsNotify = true;
    }

    _highlightedLines = newHighlightedLines;
    _codeLines = newLines;

    if (needsNotify && !initial) {
      // Immediately show the new state with un-styled new/changed lines.
      // Unchanged lines remain perfectly styled. NO FLICKER.
      notifyListeners();
    }
    
    // If there's something to highlight, schedule the background work.
    if (firstDirtyLine != -1 || initial) {
        if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 50), () {
            // Use the last modified line for the streaming case
            _runPartialHighlight(newLines.length - 1);
        });
    }
  }

  Future<void> _runPartialHighlight(int dirtyLineIndex) async {
    if (_codeLines.isEmpty) return;

    final payload = _PartialHighlightPayload(
      codeLines: _codeLines,
      dirtyLineIndex: dirtyLineIndex,
      language: language,
    );

    try {
      final Map<int, _HighlightLineResult> result = await compute(_highlightPartialIsolate, payload);

      bool didUpdate = false;
      for (final entry in result.entries) {
        final lineIndex = entry.key;
        if (lineIndex < _highlightedLines.length) {
          // IMPORTANT: Check if the code for this line hasn't changed again
          // while the isolate was running.
          final lineContent = entry.value.nodes.map((n) => n.value).join();
          if (_codeLines[lineIndex] == lineContent) {
            _highlightedLines[lineIndex] = _renderNodesToSpan(entry.value.nodes);
            didUpdate = true;
          }
        }
      }

      if (didUpdate) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Partial highlighting failed: $e");
    }
  }

  // All helper methods below are unchanged
  TextSpan _renderNodesToSpan(List<_HighlightNode> nodes) {
    if (nodes.isEmpty) return const TextSpan(text: '');
    return TextSpan(
      children: nodes.map((e) => TextSpan(
        text: e.value,
        style: _findStyle(e.className),
      )).toList(),
    );
  }

  TextStyle? _findStyle(String? className) {
    if (className == null) return null;
    return theme[className];
  }
  
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