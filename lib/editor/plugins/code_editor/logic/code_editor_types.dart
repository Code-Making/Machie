class ColorMatch {
  final int start;
  final int end;
  final Color color;
  _ColorMatch({required this.start, required this.end, required this.color});
}

class BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final Set<int> highlightedLines;
  const BracketHighlightState({
    this.bracketPositions = const {},
    this.highlightedLines = const {},
  });
}