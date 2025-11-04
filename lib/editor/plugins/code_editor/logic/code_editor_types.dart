import 'package:re_editor/re_editor.dart';
import 'package:flutter/material.dart';

class ColorMatch {
  final int start;
  final int end;
  final Color color;
  ColorMatch({required this.start, required this.end, required this.color});
}

class BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final Set<int> highlightedLines;
  const BracketHighlightState({
    this.bracketPositions = const {},
    this.highlightedLines = const {},
  });
}