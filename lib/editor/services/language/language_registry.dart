import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/latex.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';

import 'default_parsers.dart';
import 'language_models.dart';

class Languages {
  Languages._();

  // --- Public API ---

  static LanguageConfig getForFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return _byExtension[ext] ?? _plaintext;
  }

  static LanguageConfig getById(String id) {
    return _byId[id] ?? _plaintext;
  }

  static bool isSupported(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return _byExtension.containsKey(ext);
  }

  static List<LanguageConfig> get all => List.unmodifiable(_allLanguages);

  static final Map<String, LanguageConfig> _byExtension = {
    for (var lang in _allLanguages)
      for (var ext in lang.extensions) ext: lang,
  };

  static final Map<String, LanguageConfig> _byId = {
    for (var lang in _allLanguages) lang.id: lang,
  };

  // --- Optimized Parsers & Helpers ---

  /// Wraps DefaultParsers with "Pruning" checks to avoid running Regexes
  /// on lines that obviously don't contain colors or links.
  static List<ParsedSpan> _parseDefaultsOptimized(String line) {
    final spans = <ParsedSpan>[];

    // Web Links Pruning
    if (line.contains('http://') || line.contains('https://')) {
      spans.addAll(DefaultParsers.parseWebLinks(line));
    }

    // Colors Pruning
    if (line.contains('#') || line.contains('Color') || line.contains('rgb')) {
      spans.addAll(DefaultParsers.parseColors(line));
    }

    return spans;
  }

  /// Locates a quoted string after a specific keyword index.
  /// Replaces Regex like: `import\s+['"]([^'"]+)['"]`
  static LinkSpan? _findLinkAfterIndex(String line, int startIndex) {
    // 1. Find opening quote
    int quoteStart = line.indexOf("'", startIndex);
    int doubleQuoteStart = line.indexOf('"', startIndex);

    // Pick the earliest quote
    if (quoteStart == -1) {
      quoteStart = doubleQuoteStart;
    } else if (doubleQuoteStart != -1 && doubleQuoteStart < quoteStart) {
      quoteStart = doubleQuoteStart;
    }

    if (quoteStart == -1) return null;

    // 2. Find closing quote
    final quoteChar = line[quoteStart];
    final quoteEnd = line.indexOf(quoteChar, quoteStart + 1);

    if (quoteEnd == -1) return null;

    // 3. Extract
    return LinkSpan(
      start: quoteStart + 1,
      end: quoteEnd,
      target: line.substring(quoteStart + 1, quoteEnd),
    );
  }

  // --- Shared Resolver for JS/TS ---
  static List<String> _jsResolutionStrategy(String path) {
    if (path.endsWith('.ts') ||
        path.endsWith('.tsx') ||
        path.endsWith('.js') ||
        path.endsWith('.jsx')) {
      return [path];
    }
    return [
      path,
      '$path.ts',
      '$path.tsx',
      '$path.js',
      '$path.jsx',
      '$path.d.ts',
      '$path/index.ts',
      '$path/index.tsx',
      '$path/index.js',
      '$path/index.jsx',
    ];
  }

  // --- Implementations ---

  static final LanguageConfig _plaintext = LanguageConfig(
    id: 'plaintext',
    name: 'Plain Text',
    extensions: {'txt', 'text', 'gitignore', 'env', 'LICENSE', 'log', ''},
    highlightMode: langPlaintext,
    comments: const CommentConfig(singleLine: '#'),
    parser: _parseDefaultsOptimized,
  );

  static final LanguageConfig _dart = LanguageConfig(
    id: 'dart',
    name: 'Dart',
    extensions: {'dart'},
    highlightMode: langDart,
    comments: const CommentConfig(
      singleLine: '//',
      blockBegin: '/*',
      blockEnd: '*/',
    ),
    importFormatter: (path) => "import '$path';",
    parser: (line) {
      final spans = _parseDefaultsOptimized(line);
      final trimmed = line.trimLeft();

      // 1. Imports/Exports/Parts (String check instead of Regex)
      if (trimmed.startsWith('import ') ||
          trimmed.startsWith('export ') ||
          trimmed.startsWith('part ')) {
        final link = _findLinkAfterIndex(line, 0);
        if (link != null) spans.add(link);
      }
      // 2. Analysis Logs / Stack Traces (Manual parsing instead of Regex)
      // Look for ".dart:" signature
      else {
        int dartExtIndex = line.indexOf('.dart:');
        if (dartExtIndex != -1) {
          // Found potential log. Scan backwards for start of path.
          // Path starts at whitespace or beginning of line.
          int start = dartExtIndex;
          while (start > 0) {
            final char = line[start - 1];
            if (char == ' ' || char == '\t' || char == '(') break;
            start--;
          }

          // Scan forwards for line numbers (digits after :)
          int end = dartExtIndex + 6; // skip ".dart:"
          bool foundLine = false;

          // Consume Line Number
          while (end < line.length) {
            final charCode = line.codeUnitAt(end);
            if (charCode >= 48 && charCode <= 57) {
              // 0-9
              end++;
              foundLine = true;
            } else {
              break;
            }
          }

          // Optional: Consume Column Number (:5)
          if (foundLine && end < line.length && line[end] == ':') {
            int colEnd = end + 1;
            bool foundCol = false;
            while (colEnd < line.length) {
              final charCode = line.codeUnitAt(colEnd);
              if (charCode >= 48 && charCode <= 57) {
                colEnd++;
                foundCol = true;
              } else {
                break;
              }
            }
            if (foundCol) end = colEnd;
          }

          if (foundLine) {
            spans.add(
              LinkSpan(
                start: start,
                end: end,
                target: line.substring(start, end),
              ),
            );
          }
        }
      }
      return spans;
    },
  );

  static final LanguageConfig _javascript = LanguageConfig(
    id: 'javascript',
    name: 'JavaScript',
    extensions: {'js', 'jsx', 'mjs', 'cjs'},
    highlightMode: langJavascript,
    comments: const CommentConfig(
      singleLine: '//',
      blockBegin: '/*',
      blockEnd: '*/',
    ),
    importFormatter: (path) => "import '$path';",
    importResolver: _jsResolutionStrategy,
    parser: (line) {
      final spans = _parseDefaultsOptimized(line);

      // Optimization: If no quotes, no imports.
      if (!line.contains("'") && !line.contains('"')) return spans;

      // 1. "import ... from '...'"
      int fromIndex = line.indexOf(' from ');
      if (fromIndex != -1) {
        final link = _findLinkAfterIndex(line, fromIndex + 6);
        if (link != null) spans.add(link);
        return spans;
      }

      // 2. "import '...'" (Side effects) or "export ... from '...'"
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
        final link = _findLinkAfterIndex(line, 0);
        if (link != null) spans.add(link);
      }
      // 3. "require('...')"
      else {
        int requireIndex = line.indexOf('require(');
        if (requireIndex != -1) {
          final link = _findLinkAfterIndex(line, requireIndex + 8);
          if (link != null) spans.add(link);
        }
      }

      return spans;
    },
  );

  // TypeScript logic is identical to JS for imports
  static final LanguageConfig _typescript = LanguageConfig(
    id: 'typescript',
    name: 'TypeScript',
    extensions: {'ts', 'tsx'},
    highlightMode: langTypescript,
    comments: const CommentConfig(
      singleLine: '//',
      blockBegin: '/*',
      blockEnd: '*/',
    ),
    importFormatter: (path) => "import '$path';",
    importResolver: _jsResolutionStrategy,
    parser: _javascript.parser, // Reuse JS parser
  );

  static final LanguageConfig _html = LanguageConfig(
    id: 'html',
    name: 'HTML',
    extensions: {'html', 'htm', 'xhtml'},
    highlightMode: langXml,
    comments: const CommentConfig(blockBegin: '<!--', blockEnd: '-->'),
    parser: (line) {
      final spans = _parseDefaultsOptimized(line);
      if (!line.contains('=')) return spans;

      // Check src="..."
      int srcIndex = line.indexOf('src=');
      if (srcIndex != -1) {
        final link = _findLinkAfterIndex(line, srcIndex + 4);
        if (link != null) spans.add(link);
      }

      // Check href="..."
      int hrefIndex = line.indexOf('href=');
      if (hrefIndex != -1) {
        final link = _findLinkAfterIndex(line, hrefIndex + 5);
        if (link != null) spans.add(link);
      }
      return spans;
    },
  );

  static final LanguageConfig _css = LanguageConfig(
    id: 'css',
    name: 'CSS',
    extensions: {'css', 'scss', 'less'},
    highlightMode: langCss,
    comments: const CommentConfig(blockBegin: '/*', blockEnd: '*/'),
    importFormatter: (path) => "@import '$path';",
    parser: (line) {
      final spans = _parseDefaultsOptimized(line);

      // @import "..."
      if (line.contains('@import')) {
        final link = _findLinkAfterIndex(line, line.indexOf('@import'));
        if (link != null) spans.add(link);
      }

      // url(...)
      int urlIndex = line.indexOf('url(');
      if (urlIndex != -1) {
        // url() can contain quotes or raw text.
        // We handle quotes via helper, raw text manually if needed.
        final link = _findLinkAfterIndex(line, urlIndex + 4);
        if (link != null) {
          spans.add(link);
        } else {
          // Handle unquoted url(path)
          int closeParen = line.indexOf(')', urlIndex);
          if (closeParen != -1) {
            spans.add(
              LinkSpan(
                start: urlIndex + 4,
                end: closeParen,
                target: line.substring(urlIndex + 4, closeParen).trim(),
              ),
            );
          }
        }
      }
      return spans;
    },
  );

  static final LanguageConfig _cpp = LanguageConfig(
    id: 'cpp',
    name: 'C++',
    extensions: {'cpp', 'c', 'cc', 'h', 'hpp'},
    highlightMode: langCpp,
    comments: const CommentConfig(
      singleLine: '//',
      blockBegin: '/*',
      blockEnd: '*/',
    ),
    importFormatter: (path) => '#include "$path"',
    parser: (line) {
      final spans = _parseDefaultsOptimized(line);
      if (line.trimLeft().startsWith('#include')) {
        final link = _findLinkAfterIndex(line, 0);
        if (link != null) {
          spans.add(link);
        } else {
          // Handle angle brackets <...>
          int startAngle = line.indexOf('<');
          int endAngle = line.indexOf('>', startAngle);
          if (startAngle != -1 && endAngle != -1) {
            spans.add(
              LinkSpan(
                start: startAngle + 1,
                end: endAngle,
                target: line.substring(startAngle + 1, endAngle),
              ),
            );
          }
        }
      }
      return spans;
    },
  );

  static final LanguageConfig _markdown = LanguageConfig(
    id: 'markdown',
    name: 'Markdown',
    extensions: {'md', 'markdown'},
    highlightMode: langMarkdown,
    comments: const CommentConfig(singleLine: '>'),
    parser: (line) {
      final spans = _parseDefaultsOptimized(line);
      // Markdown is complex, keeping a simple manual check for standard link structure `](...`
      int closeBracket = line.indexOf('](');
      while (closeBracket != -1) {
        int closeParen = line.indexOf(')', closeBracket);
        if (closeParen != -1) {
          spans.add(
            LinkSpan(
              start: closeBracket + 2,
              end: closeParen,
              target: line.substring(closeBracket + 2, closeParen),
            ),
          );
        }
        closeBracket = line.indexOf('](', closeBracket + 2);
      }
      return spans;
    },
  );

  static final LanguageConfig _latex = LanguageConfig(
    id: 'latex',
    name: 'LaTeX',
    extensions: {'tex', 'sty', 'cls'},
    highlightMode: langLatex,
    comments: const CommentConfig(singleLine: '%'),
    importFormatter: (path) => '\\input{$path}',
    parser: (line) {
      final spans = _parseDefaultsOptimized(line);
      // Pruning
      if (!line.contains(r'\')) return spans;

      for (final cmd in [r'\input{', r'\include{', r'\includegraphics']) {
        int cmdIndex = line.indexOf(cmd);
        if (cmdIndex != -1) {
          int openBrace = line.indexOf('{', cmdIndex);
          if (openBrace != -1) {
            int closeBrace = line.indexOf('}', openBrace);
            if (closeBrace != -1) {
              spans.add(
                LinkSpan(
                  start: openBrace + 1,
                  end: closeBrace,
                  target: line.substring(openBrace + 1, closeBrace),
                ),
              );
            }
          }
        }
      }
      return spans;
    },
  );

  static final List<LanguageConfig> _allLanguages = [
    _plaintext,
    _dart,
    _javascript,
    _typescript,
    _html,
    _css,
    _cpp,
    _markdown,
    _latex,
    // Standard configurations (no custom parsing needed)
    LanguageConfig(
      id: 'python',
      name: 'Python',
      extensions: {'py', 'pyw'},
      highlightMode: langPython,
      comments: const CommentConfig(singleLine: '#'),
      parser: _parseDefaultsOptimized,
    ),
    LanguageConfig(
      id: 'java',
      name: 'Java',
      extensions: {'java'},
      highlightMode: langJava,
      comments: const CommentConfig(
        singleLine: '//',
        blockBegin: '/*',
        blockEnd: '*/',
      ),
      parser: _parseDefaultsOptimized,
    ),
    LanguageConfig(
      id: 'kotlin',
      name: 'Kotlin',
      extensions: {'kt', 'kts'},
      highlightMode: langKotlin,
      comments: const CommentConfig(
        singleLine: '//',
        blockBegin: '/*',
        blockEnd: '*/',
      ),
      parser: _parseDefaultsOptimized,
    ),
    LanguageConfig(
      id: 'bash',
      name: 'Bash',
      extensions: {'sh', 'bash', 'zsh'},
      highlightMode: langBash,
      comments: const CommentConfig(singleLine: '#'),
      parser: _parseDefaultsOptimized,
    ),
    LanguageConfig(
      id: 'json',
      name: 'JSON',
      extensions: {'json', 'arb', 'ipynb'},
      highlightMode: langJson,
      parser: _parseDefaultsOptimized,
    ),
    LanguageConfig(
      id: 'xml',
      name: 'XML',
      extensions: {'xml', 'xsd', 'svg', 'plist', 'manifest'},
      highlightMode: langXml,
      comments: const CommentConfig(blockBegin: '<!--', blockEnd: '-->'),
      parser: _parseDefaultsOptimized,
    ),
    LanguageConfig(
      id: 'yaml',
      name: 'YAML',
      extensions: {'yaml', 'yml'},
      highlightMode: langYaml,
      comments: const CommentConfig(singleLine: '#'),
      parser: _parseDefaultsOptimized,
    ),
    LanguageConfig(
      id: 'properties',
      name: 'Properties',
      extensions: {'properties', 'conf', 'ini'},
      highlightMode: langProperties,
      comments: const CommentConfig(singleLine: '#'),
      parser: _parseDefaultsOptimized,
    ),
  ];
}
