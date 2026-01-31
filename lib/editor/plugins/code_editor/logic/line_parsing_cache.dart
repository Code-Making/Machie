import '../../../services/language/parsed_span_models.dart';

/// Caches parsing results (Links, Colors) based on line content strings.
/// This avoids re-running expensive Regex on lines that haven't changed.
class LineParsingCache {
  // Map content string -> List of parsed data models
  // Using String as key is efficient in Dart due to string interning.
  final Map<String, List<ParsedSpan>> _cache = {};

  /// Retrieves cached spans for the given text, if available.
  List<ParsedSpan>? get(String text) {
    return _cache[text];
  }

  /// Stores spans for the given text.
  void set(String text, List<ParsedSpan> spans) {
    _cache[text] = spans;
  }

  /// Clears the cache. Call this when language changes or memory needs freeing.
  void clear() {
    _cache.clear();
  }
}