import 'dart:ui';
import 'parsed_span_models.dart';

class DefaultParsers {
  // Pre-compile Regexes once (static final)
  static final _hexColorRegex = RegExp(r'(?<!\w)#([A-Fa-f0-9]{8}|[A-Fa-f0-9]{6})\b');
  static final _shortHexColorRegex = RegExp(r'(?<!\w)#([A-Fa-f0-9]{3,4})\b');
  static final _colorCtorRegex = RegExp(r'Color\(\s*(0x[A-Fa-f0-9]{1,8})\s*\)');
  
  // Optimized URL regex: Removed unbound backtracking risks slightly
  static final _urlRegex = RegExp(r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)');

  static List<ParsedSpan> parseAll(String line) {
    final spans = <ParsedSpan>[];
    
    // 1. Check for Color triggers before running color parsing
    if (line.contains('#') || line.contains('Color')) {
      spans.addAll(parseColors(line));
    }

    // 2. Check for Link triggers before running URL parsing
    if (line.contains('http')) {
      spans.addAll(parseWebLinks(line));
    }

    return spans;
  }

  static List<LinkSpan> parseWebLinks(String line) {
    // FAIL-FAST: 99% of lines don't have links. Don't run Regex.
    if (!line.contains('http')) return [];

    final matches = <LinkSpan>[];
    for (final m in _urlRegex.allMatches(line)) {
      matches.add(LinkSpan(start: m.start, end: m.end, target: m.group(0)!));
    }
    return matches;
  }

  static List<ColorSpan> parseColors(String line) {
    final matches = <ColorSpan>[];
    
    // FAIL-FAST checks
    final hasHash = line.contains('#');
    final hasColorCtor = line.contains('Color(');

    if (!hasHash && !hasColorCtor) return [];

    // 1. Hex Colors (#RRGGBB, #AARRGGBB, #RGB)
    if (hasHash) {
      // Run Hex regexes
      for (final m in _hexColorRegex.allMatches(line)) {
        _addHexMatch(matches, m, 6); // Helper method to reduce code duplication
      }
      for (final m in _shortHexColorRegex.allMatches(line)) {
        _addHexMatch(matches, m, 3);
      }
    }

    // 2. Dart/Flutter Color(0xFF...)
    if (hasColorCtor) {
      for (final m in _colorCtorRegex.allMatches(line)) {
        final hex = m.group(1);
        if (hex != null) {
          final val = int.tryParse(hex.substring(2), radix: 16);
          if (val != null) {
            matches.add(ColorSpan(
              start: m.start,
              end: m.end,
              color: Color(val),
              originalText: m.group(0)!,
            ));
          }
        }
      }
    }

    return matches;
  }

  // Helper to handle Hex logic cleanly
  static void _addHexMatch(List<ColorSpan> matches, RegExpMatch m, int type) {
    String hex = m.group(1)!;
    if (type == 3) {
       // Expansion logic for #RGB -> #RRGGBB
       hex = hex.length == 3 
           ? hex.split('').map((e) => e + e).join() 
           : hex[0] + hex[0] + hex.substring(1).split('').map((e) => e + e).join();
    }
    final val = int.tryParse(hex, radix: 16);
    if (val != null) {
      final color = hex.length == 8 ? Color(val) : Color(0xFF000000 | val);
      matches.add(ColorSpan(
        start: m.start,
        end: m.end,
        color: color,
        originalText: m.group(0)!,
      ));
    }
  }
}