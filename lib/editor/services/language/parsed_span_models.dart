import 'dart:ui';

import 'package:flutter/foundation.dart';

/// A function signature for parsing a line of text into interactable spans.
typedef SpanParser = List<ParsedSpan> Function(String lineContent);

/// The base class for any region in the code that needs special rendering
/// or interaction (beyond standard syntax highlighting).
@immutable
sealed class ParsedSpan {
  final int start;
  final int end;

  const ParsedSpan({required this.start, required this.end});
}

/// Represents a clickable link (imports, URLs, file paths with line numbers).
class LinkSpan extends ParsedSpan {
  /// The raw string to act upon (e.g., "package:flutter/material.dart",
  /// "https://google.com", or "/lib/main.dart:42:5").
  final String target;

  const LinkSpan({
    required super.start,
    required super.end,
    required this.target,
  });

  @override
  String toString() => 'LinkSpan($start-$end, target: $target)';
}

/// Represents a color code (hex, RGB, etc.) that should be highlighted.
class ColorSpan extends ParsedSpan {
  final Color color;

  /// The original text format (e.g. "#FFFFFF" vs "Color(0xFFFFFFFF)")
  /// Used to ensure we respect the user's format when modifying it.
  final String originalText;

  const ColorSpan({
    required super.start,
    required super.end,
    required this.color,
    required this.originalText,
  });

  @override
  String toString() => 'ColorSpan($start-$end, color: $color)';
}
