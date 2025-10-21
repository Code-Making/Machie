// FILE: lib/editor/plugins/llm_editor/code_block_controller.dart

import 'dart:async';
import 'package.dart';
import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/llm_editor/llm_highlight_util.dart';
import 'package:re_highlight/re_highlight.dart';

// Payload for the isolate. This is a pure data class.
class _HighlightPayload {
  final String code;
  final String language;
  _HighlightPayload(this.code, this.language);
}

// Data class to return from the isolate. Contains only Dart primitives.
class _HighlightResultData {
  final List<Object?> nodes;
  _HighlightResultData(this.nodes);
}

// Top-level function for the isolate.
// It performs the heavy lifting and returns pure data.
_HighlightResultData _highlightIsolate(_HighlightPayload payload) {
  LlmHighlightUtil.ensureLanguagesRegistered();
  final result = LlmHighlightUtil.highlight.highlight(
    code: payload.code,
    language: payload.language,
  );
  return _HighlightResultData(result.nodes ?? []);
}


class CodeBlockController extends ChangeNotifier {
  final TextStyle textStyle;
  final Map<String, TextStyle> theme;

  // The final TextSpan ready for the UI.
  TextSpan? _highlightedCode;
  // The latest version of the code from the stream.
  String _currentCode;
  // The last version of the code we sent to be highlighted.
  String? _lastProcessedCode;
  
  bool _isFolded = false;
  // A periodic timer acting as a throttle.
  Timer? _throttleTimer;
  // Flag to prevent multiple concurrent highlight operations.
  bool _isHighlighting = false;
  // How often we should update the highlighting during a stream.
  static const _throttleDuration = Duration(milliseconds: 250);


  CodeBlockController({
    required String initialCode,
    required this.language,
    required this.textStyle,
    required this.theme,
  }) : _currentCode = initialCode {
    // Perform initial highlighting immediately, not throttled.
    _runHighlight();
  }
  
  // Stored language to avoid passing it on every update.
  final String language;

  TextSpan? get highlightedCode => _highlightedCode;
  bool get isFolded => _isFolded;
  
  void toggleFold() {
    _isFolded = !_isFolded;
    notifyListeners();
  }

  /// Called frequently by the widget when new code streams in.
  void updateCode(String newCode) {
    _currentCode = newCode;
    // If the throttle timer isn't running, start it.
    _throttleTimer ??= Timer.periodic(_throttleDuration, _onThrottleTick);
  }

  // The throttle callback.
  void _onThrottleTick(Timer timer) {
    // If there's new code to process and we're not already busy, run the highlight.
    if (_currentCode != _lastProcessedCode && !_isHighlighting) {
      _runHighlight();
    }
  }

  Future<void> _runHighlight() async {
    // If we're already highlighting, do nothing.
    if (_isHighlighting) return;

    _isHighlighting = true;
    _lastProcessedCode = _currentCode;
    final codeToProcess = _currentCode;

    final payload = _HighlightPayload(codeToProcess, language);

    try {
      final _HighlightResultData resultData = await compute(_highlightIsolate, payload);

      // Only update if the code we processed is still the latest version.
      // This prevents a slow highlight from overwriting a newer, faster one.
      if (codeToProcess == _currentCode) {
        final renderer = TextSpanRenderer(textStyle, theme);
        // Re-construct the HighlightResult on the main thread
        final result = HighlightResult(nodes: resultData.nodes);
        result.render(renderer);
        
        _highlightedCode = renderer.span;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Highlighting failed: $e");
      // Fallback to plain text on error.
      _highlightedCode = TextSpan(text: codeToProcess, style: textStyle);
      notifyListeners();
    } finally {
      _isHighlighting = false;
    }
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    super.dispose();
  }
}