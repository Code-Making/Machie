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
  int _highlightGeneration = 0; // Generation counter to discard stale results

  String getFullCode() => _codeLines.join('\n');

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
    
    // Immediately update UI with plain text for changed parts to avoid flicker.
    // This is cheap and ensures responsiveness.
    bool needsNotify = _codeLines.length != newLines.length;
    final newHighlightedLines = <TextSpan>[];
    for (int i = 0; i < newLines.length; i++) {
      if (i < _codeLines.length && newLines[i] == _codeLines[i]) {
        newHighlightedLines.add(_highlightedLines[i]); // Reuse old span
      } else {
        newHighlightedLines.add(TextSpan(text: newLines[i])); // New or changed line
        needsNotify = true;
      }
    }

    _highlightedLines = newHighlightedLines;
    _codeLines = newLines;

    if (needsNotify && !initial) {
      notifyListeners();
    }
    
    // Cancel any pending work and start a new, full highlighting pass in chunks.
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _highlightGeneration++; // Invalidate previous work
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _processHighlightQueue(0, _highlightGeneration);
    });
  }

  // Asynchronously processes the entire code block in managed chunks.
  void _processHighlightQueue(int startLine, int generation) async {
    // If a new update came in, abandon this old work.
    if (generation != _highlightGeneration || startLine >= _codeLines.length) {
      return;
    }

    const int contextSize = 30;
    const int chunkSize = contextSize * 2 + 1;
    // The "dirty" line is the center of our processing window for this chunk.
    final int dirtyLineIndex = startLine + contextSize;

    final payload = _PartialHighlightPayload(
      codeLines: _codeLines,
      dirtyLineIndex: dirtyLineIndex,
      language: language,
    );

    try {
      final result = await compute(_highlightPartialIsolate, payload);
      
      // Check generation again after the await.
      if (generation != _highlightGeneration) return;
      
      bool didUpdate = false;
      for (final entry in result.entries) {
        final lineIndex = entry.key;
        if (lineIndex < _highlightedLines.length) {
          _highlightedLines[lineIndex] = _renderNodesToSpan(entry.value.nodes);
          didUpdate = true;
        }
      }

      if (didUpdate) {
        notifyListeners();
      }

      // Schedule the next chunk of work, yielding to the event loop.
      Future.delayed(Duration.zero, () {
        _processHighlightQueue(startLine + chunkSize, generation);
      });

    } catch (e) {
      debugPrint("Chunked highlighting failed: $e");
    }
  }

  // --- Helper Methods (unchanged) ---
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