// lib/editor/services/language/default_parsers.dart

import 'dart:ui';

import 'parsed_span_models.dart';

/// Centralized logic for parsing common patterns found in most languages.
class DefaultParsers {
  // --- Regex Definitions (Moved from CodeEditorUtils) ---

  static final _hexColorRegex = RegExp(
    r'(?<!\w)#([A-Fa-f0-9]{8}|[A-Fa-f0-9]{6})\b',
  );
  static final _shortHexColorRegex = RegExp(r'(?<!\w)#([A-Fa-f0-9]{3,4})\b');
  static final _colorCtorRegex = RegExp(r'Color\(\s*(0x[A-Fa-f0-9]{1,8})\s*\)');
  static final _urlRegex = RegExp(
    r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
  );

  /// Runs all default parsers (Colors, Web URLs) on the line.
  static List<ParsedSpan> parseAll(String line) {
    return [...parseColors(line), ...parseWebLinks(line)];
  }

  static List<LinkSpan> parseWebLinks(String line) {
    final matches = <LinkSpan>[];
    for (final m in _urlRegex.allMatches(line)) {
      matches.add(LinkSpan(start: m.start, end: m.end, target: m.group(0)!));
    }
    return matches;
  }

  static List<ColorSpan> parseColors(String line) {
    final matches = <ColorSpan>[];

    // 1. Hex Colors (#RRGGBB, #AARRGGBB)
    for (final m in _hexColorRegex.allMatches(line)) {
      final hex = m.group(1)!;
      final val = int.tryParse(hex, radix: 16);
      if (val != null) {
        final color = hex.length == 8 ? Color(val) : Color(0xFF000000 | val);
        matches.add(
          ColorSpan(
            start: m.start,
            end: m.end,
            color: color,
            originalText: m.group(0)!,
          ),
        );
      }
    }

    // 2. Short Hex (#RGB, #RGBA)
    for (final m in _shortHexColorRegex.allMatches(line)) {
      String hex = m.group(1)!;
      hex =
          hex.length == 3
              ? hex.split('').map((e) => e + e).join()
              : hex[0] +
                  hex[0] +
                  hex.substring(1).split('').map((e) => e + e).join();
      final val = int.tryParse(hex, radix: 16);
      if (val != null) {
        final color = hex.length == 8 ? Color(val) : Color(0xFF000000 | val);
        matches.add(
          ColorSpan(
            start: m.start,
            end: m.end,
            color: color,
            originalText: m.group(0)!,
          ),
        );
      }
    }

    // 3. Dart/Flutter Color(0xFF...)
    for (final m in _colorCtorRegex.allMatches(line)) {
      final hex = m.group(1);
      if (hex != null) {
        final val = int.tryParse(hex.substring(2), radix: 16);
        if (val != null) {
          matches.add(
            ColorSpan(
              start: m.start,
              end: m.end,
              color: Color(val),
              originalText: m.group(0)!,
            ),
          );
        }
      }
    }

    // Note: Add fromARGB and fromRGBO parsers here as needed (omitted for brevity)

    return matches;
  }
}
