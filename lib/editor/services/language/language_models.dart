// lib/editor/services/language/language_models.dart

import 'package:re_highlight/re_highlight.dart';

import 'default_parsers.dart';
import 'parsed_span_models.dart';

export 'parsed_span_models.dart';

class LanguageConfig {
  final String id;
  final String name;
  final Set<String> extensions;
  final Mode? highlightMode;
  final CommentConfig? comments;

  /// A unified parser that returns both Links and Colors for a given line.
  final SpanParser parser;

  /// Optional formatter for inserting new imports (used by "Add Import" action).
  final String Function(String path)? importFormatter;

  /// Optional resolver to handle implicit extensions or directory indices.
  /// Converts a raw import string (e.g. './utils') into a list of potential
  /// file paths to probe on the file system (e.g. ['./utils.ts', './utils/index.ts']).
  final List<String> Function(String importPath)? importResolver;

  LanguageConfig({
    required this.id,
    required this.name,
    required this.extensions,
    this.highlightMode,
    this.comments,
    SpanParser? parser,
    this.importFormatter,
    this.importResolver,
  }) : parser = parser ?? _defaultParser;

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
