import 'package:flutter/material.dart';

import 'package:re_editor/re_editor.dart';

class ColorMatch {
  final int start;
  final int end;
  final Color color;
  final String text;

  ColorMatch({
    required this.start,
    required this.end,
    required this.color,
    required this.text,
  });
}

class BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final Set<int> highlightedLines;
  const BracketHighlightState({
    this.bracketPositions = const {},
    this.highlightedLines = const {},
  });
}
