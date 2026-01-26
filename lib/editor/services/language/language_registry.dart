// lib/editor/services/language/language_registry.dart

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

  /// Extracts content between quotes (' or ") found in the regex match.
  static List<LinkSpan> _parseQuotedLinks(String line, List<RegExp> patterns) {
    final spans = <LinkSpan>[];
    for (final regex in patterns) {
      for (final match in regex.allMatches(line)) {
        final text = match.group(0)!;
        
        int quoteStart = text.indexOf("'");
        if (quoteStart == -1) quoteStart = text.indexOf('"');
        if (quoteStart == -1) continue;

        final quoteChar = text[quoteStart];
        final quoteEnd = text.indexOf(quoteChar, quoteStart + 1);
        if (quoteEnd == -1) continue;

        final absoluteStart = match.start + quoteStart + 1;
        final absoluteEnd = match.start + quoteEnd;

        if (absoluteEnd > absoluteStart) {
          spans.add(LinkSpan(
            start: absoluteStart,
            end: absoluteEnd,
            target: text.substring(quoteStart + 1, quoteEnd),
          ));
        }
      }
    }
    return spans;
  }

  // --- Implementations ---

  // REFACTORED: Plain Text now simply uses default parsers.
  static final LanguageConfig _plaintext = LanguageConfig(
    id: 'plaintext',
    name: 'Plain Text',
    extensions: {'txt', 'text', 'gitignore', 'env', 'LICENSE', 'log', ''},
    highlightMode: langPlaintext,
    comments: const CommentConfig(singleLine: '#'),
    parser: (line) => DefaultParsers.parseAll(line),
  );

  static final List<LanguageConfig> _allLanguages = [
    _plaintext,
    LanguageConfig(
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
        // 1. Defaults (Colors, Web Links)
        final spans = DefaultParsers.parseAll(line);
        
        // 2. Imports/Exports
        spans.addAll(_parseQuotedLinks(line, [
          RegExp(r'''import\s+['"][^'"]+['"]'''),
          RegExp(r'''export\s+['"][^'"]+['"]'''),
          RegExp(r'''part\s+(?:of\s+)?['"][^'"]+['"]'''),
        ]));

        // 3. Analysis Logs / Stack Traces
        // Regex: Matches any non-whitespace string ending in .dart followed by :row and optional :col
        // Example matches: 
        //   lib/main.dart:10:5
        //   package:foo/bar.dart:42
        //   /abs/path/file.dart:10
        final logRegex = RegExp(r'([^\s]+\.dart):(\d+)(?::(\d+))?');

        for (final m in logRegex.allMatches(line)) {
          spans.add(LinkSpan(
            start: m.start,
            end: m.end,
            target: m.group(0)!, 
          ));
        }
        
        return spans;
      },
    ),
    LanguageConfig(
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
      parser: (line) {
        final spans = DefaultParsers.parseAll(line);
        spans.addAll(_parseQuotedLinks(line, [
          RegExp(r'''from\s+['"][^'"]+['"]'''),
          RegExp(r'''import\s+['"][^'"]+['"]'''),
          RegExp(r'''require\s*\(\s*['"][^'"]+['"]\s*\)'''),
        ]));
        return spans;
      },
    ),
    LanguageConfig(
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
      parser: (line) {
        final spans = DefaultParsers.parseAll(line);
        spans.addAll(_parseQuotedLinks(line, [
          RegExp(r'''from\s+['"][^'"]+['"]'''),
          RegExp(r'''import\s+['"][^'"]+['"]'''),
          RegExp(r'''require\s*\(\s*['"][^'"]+['"]\s*\)'''),
        ]));
        return spans;
      },
    ),
    LanguageConfig(
      id: 'html',
      name: 'HTML',
      extensions: {'html', 'htm', 'xhtml'},
      highlightMode: langXml,
      comments: const CommentConfig(blockBegin: '<!--', blockEnd: '-->'),
      parser: (line) {
        final spans = DefaultParsers.parseAll(line);
        spans.addAll(_parseQuotedLinks(line, [
          RegExp(r'''src=["'][^"']+["']'''),
          RegExp(r'''href=["'][^"']+["']'''),
        ]));
        return spans;
      },
    ),
    LanguageConfig(
      id: 'css',
      name: 'CSS',
      extensions: {'css', 'scss', 'less'},
      highlightMode: langCss,
      comments: const CommentConfig(blockBegin: '/*', blockEnd: '*/'),
      importFormatter: (path) => "@import '$path';",
      parser: (line) {
        final spans = DefaultParsers.parseAll(line);
        spans.addAll(_parseQuotedLinks(line, [
          RegExp(r'''@import\s+["'][^"']+["']'''),
          RegExp(r'''url\s*\(\s*["']?[^"')]+["']?\s*\)'''),
        ]));
        return spans;
      },
    ),
    LanguageConfig(
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
        final spans = DefaultParsers.parseAll(line);
        spans.addAll(_parseQuotedLinks(line, [
          RegExp(r'''#include\s+["'][^"']+["']''')
        ]));
        return spans;
      },
    ),
    LanguageConfig(
      id: 'markdown',
      name: 'Markdown',
      extensions: {'md', 'markdown'},
      highlightMode: langMarkdown,
      comments: const CommentConfig(singleLine: '>'),
      parser: (line) {
        final spans = DefaultParsers.parseAll(line);
        final linkRegex = RegExp(r'\]\(([^)]+)\)');
        for (final m in linkRegex.allMatches(line)) {
          final matchText = m.group(0)!;
          final openParenIndex = matchText.lastIndexOf('(');
          if (openParenIndex != -1) {
             spans.add(LinkSpan(
               start: m.start + openParenIndex + 1,
               end: m.end - 1,
               target: m.group(1)!,
             ));
          }
        }
        return spans;
      },
    ),
    LanguageConfig(
      id: 'latex',
      name: 'LaTeX',
      extensions: {'tex', 'sty', 'cls'},
      highlightMode: langLatex,
      comments: const CommentConfig(singleLine: '%'),
      importFormatter: (path) => '\\input{$path}',
      parser: (line) {
        final spans = DefaultParsers.parseAll(line);
        final latexPatterns = [
          RegExp(r'''\\input\{([^}]+)\}'''),
          RegExp(r'''\\include\{([^}]+)\}'''),
          RegExp(r'''\\includegraphics(?:\[.*\])?\{([^}]+)\}'''),
        ];
        
        for (final regex in latexPatterns) {
          for (final m in regex.allMatches(line)) {
            final matchText = m.group(0)!;
            final openBrace = matchText.lastIndexOf('{');
            final closeBrace = matchText.indexOf('}', openBrace);
            
            if (openBrace != -1 && closeBrace != -1) {
              spans.add(LinkSpan(
                start: m.start + openBrace + 1,
                end: m.start + closeBrace,
                target: m.group(1)!,
              ));
            }
          }
        }
        return spans;
      },
    ),
    // Standard configurations
    LanguageConfig(
      id: 'python',
      name: 'Python',
      extensions: {'py', 'pyw'},
      highlightMode: langPython,
      comments: const CommentConfig(singleLine: '#'),
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
    ),
    LanguageConfig(
      id: 'bash',
      name: 'Bash',
      extensions: {'sh', 'bash', 'zsh'},
      highlightMode: langBash,
      comments: const CommentConfig(singleLine: '#'),
    ),
    LanguageConfig(
      id: 'json',
      name: 'JSON',
      extensions: {'json', 'arb', 'ipynb'},
      highlightMode: langJson,
    ),
    LanguageConfig(
      id: 'xml',
      name: 'XML',
      extensions: {'xml', 'xsd', 'svg', 'plist', 'manifest'},
      highlightMode: langXml,
      comments: const CommentConfig(blockBegin: '<!--', blockEnd: '-->'),
    ),
    LanguageConfig(
      id: 'yaml',
      name: 'YAML',
      extensions: {'yaml', 'yml'},
      highlightMode: langYaml,
      comments: const CommentConfig(singleLine: '#'),
    ),
    LanguageConfig(
      id: 'properties',
      name: 'Properties',
      extensions: {'properties', 'conf', 'ini'},
      highlightMode: langProperties,
      comments: const CommentConfig(singleLine: '#'),
    ),
  ];
}