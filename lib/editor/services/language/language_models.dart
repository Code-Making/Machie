// lib/editor/services/language/language_models.dart

import 'package:re_highlight/re_highlight.dart';
import 'parsed_span_models.dart';

export 'parsed_span_models.dart';
import 'default_parsers.dart';

class LanguageConfig {
  final String id;
  final String name;
  final Set<String> extensions;
  final Mode? highlightMode;
  final CommentConfig? comments;
  
  /// A unified parser that returns both Links and Colors for a given line.
  /// Defaults to [DefaultParsers.parseAll] if not provided.
  final SpanParser parser;

  /// Optional formatter for inserting new imports (used by "Add Import" action).
  final String Function(String path)? importFormatter;

  LanguageConfig({
    required this.id,
    required this.name,
    required this.extensions,
    this.highlightMode,
    this.comments,
    SpanParser? parser,
    this.importFormatter,
  }) : parser = parser ?? _defaultParser;

  // Default implementation if no specific parser is provided
  static List<ParsedSpan> _defaultParser(String line) {
    return [
      ...DefaultParsers.parseColors(line),
      ...DefaultParsers.parseWebLinks(line),
    ];
  }
}

class CommentConfig {
  final String singleLine;
  final String? blockBegin;
  final String? blockEnd;

  const CommentConfig({this.singleLine = '', this.blockBegin, this.blockEnd});
}