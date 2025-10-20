// NEW FILE: lib/editor/plugins/llm_editor/code_block_controller.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/llm_editor/llm_highlight_util.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:machine/editor/plugins/llm_editor/markdown_builders.dart'; // For PathLinkBuilder

// Payload for the isolate
class _HighlightPayload {
  final String code;
  final String language;

  _HighlightPayload(this.code, this.language);
}

// The top-level function to be executed in an isolate
HighlightResult _highlightIsolate(_HighlightPayload payload) {
  LlmHighlightUtil.ensureLanguagesRegistered();
  return LlmHighlightUtil.highlight.highlight(
    code: payload.code,
    language: payload.language,
  );
}


class CodeBlockController extends ChangeNotifier {
  final TextStyle textStyle;
  final Map<String, TextStyle> theme;

  TextSpan? _highlightedCode;
  bool _isFolded = false;
  Timer? _debounceTimer;

  CodeBlockController({
    required String initialCode,
    required String language,
    required this.textStyle,
    required this.theme,
  }) {
    // Perform initial highlighting immediately.
    _updateHighlight(initialCode, language);
  }
  
  TextSpan? get highlightedCode => _highlightedCode;
  bool get isFolded => _isFolded;
  
  void toggleFold() {
    _isFolded = !_isFolded;
    notifyListeners();
  }

  void updateCode(String newCode, String language) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      _updateHighlight(newCode, language);
    });
  }

  Future<void> _updateHighlight(String code, String language) async {
    final payload = _HighlightPayload(code, language);

    try {
      // Run the expensive highlighting in a background isolate
      final HighlightResult result = await compute(_highlightIsolate, payload);

      // Render the result back into a TextSpan on the main thread
      final renderer = TextSpanRenderer(textStyle, theme);
      result.render(renderer);
      
      _highlightedCode = renderer.span;
      
    } catch (e) {
      // Fallback to plain text on error
      _highlightedCode = TextSpan(text: code, style: textStyle);
    }
    
    // Notify listeners that the new TextSpan is ready
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}