import 'package:re_highlight/re_highlight.dart';

class LanguageConfig {
  final String id;
  final String name;
  final Set<String> extensions;
  final Mode? highlightMode;
  final CommentConfig? comments;
  final String Function(String path)? importFormatter;
  final List<RegExp> importPatterns;
  final List<String> importIgnoredPrefixes;

  const LanguageConfig({
    required this.id,
    required this.name,
    required this.extensions,
    this.highlightMode,
    this.comments,
    this.importFormatter,
    this.importPatterns = const [],
    this.importIgnoredPrefixes = const [],
  });
}

class CommentConfig {
  final String singleLine;
  final String? blockBegin;
  final String? blockEnd;

  const CommentConfig({this.singleLine = '', this.blockBegin, this.blockEnd});
}
