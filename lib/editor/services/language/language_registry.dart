import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/editor_plugin_registry.dart';
import 'package:re_highlight/languages/all.dart';
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

import 'language_models.dart';
import 'package:re_highlight/languages/all.dart';

class Languages {
  // Private constructor to prevent instantiation
  Languages._();

  // --- Public API ---

  /// Returns the config for a given filename, or the fallback (Plain Text) if not found.
  static LanguageConfig getForFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return _byExtension[ext] ?? _plaintext;
  }
  
    /// Returns the config for a specific Language ID (e.g., 'cpp', 'dart').
  static LanguageConfig getById(String id) {
    return _byId[id] ?? _plaintext;
  }

  /// Returns true if we have explicit support (highlighting/features) for this file.
  static bool isSupported(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return _byExtension.containsKey(ext);
  }
  
  /// Returns all registered languages (for UI selection).
  static List<LanguageConfig> get all => List.unmodifiable(_allLanguages);


  // --- Internal Maps (Lazily initialized if needed, or just static const if possible) ---
  // Since Mode objects are not const, we use a static final map.
  
  static final Map<String, LanguageConfig> _byExtension = {
    for (var lang in _allLanguages)
      for (var ext in lang.extensions) ext: lang
  };
  
  static final Map<String, LanguageConfig> _byId = {
    for (var lang in _allLanguages) lang.id: lang
  };

  static final LanguageConfig _plaintext = LanguageConfig(
    id: 'plaintext',
    name: 'Plain Text',
    extensions: {'txt', 'text', 'gitignore', 'env', 'LICENSE', ''},
    highlightMode: langPlaintext,
    comments: const CommentConfig(singleLine: '#'), // Common default for config files
  );

  // --- The Data Definitions ---

  static final List<LanguageConfig> _allLanguages = [
    _plaintext,
    // --- DART ---
    LanguageConfig(
      id: 'dart',
      name: 'Dart',
      extensions: {'dart'},
      highlightMode: langDart,
      comments: const CommentConfig(singleLine: '//', blockBegin: '/*', blockEnd: '*/'),
      importFormatter: (path) => "import '$path';",
      importIgnoredPrefixes: ['dart:', 'package:', 'http:', 'https:'],
      importPatterns: [
        RegExp(r'''import\s+['"]([^'"]+)['"]'''),
        RegExp(r'''export\s+['"]([^'"]+)['"]'''),
        RegExp(r'''part\s+(?:of\s+)?['"]([^'"]+)['"]'''),
      ],
    ),

    // --- JAVASCRIPT ---
    LanguageConfig(
      id: 'javascript',
      name: 'JavaScript',
      extensions: {'js', 'jsx', 'mjs', 'cjs'},
      highlightMode: langJavascript,
      comments: const CommentConfig(singleLine: '//', blockBegin: '/*', blockEnd: '*/'),
      importFormatter: (path) => "import '$path';",
      importIgnoredPrefixes: ['http:', 'https:', 'node:'],
      importPatterns: [
        // Matches: import ... from 'path' (ES Modules)
        RegExp(r'''from\s+['"]([^'"]+)['"]'''),
        // Matches: import 'path' (Side-effect imports)
        RegExp(r'''import\s+['"]([^'"]+)['"]'''),
        // Matches: require('path') (CommonJS)
        RegExp(r'''require\s*\(\s*['"]([^'"]+)['"]\s*\)'''),
      ],
    ),

    // --- TYPESCRIPT ---
    LanguageConfig(
      id: 'typescript',
      name: 'TypeScript',
      extensions: {'ts', 'tsx'},
      highlightMode: langTypescript,
      comments: const CommentConfig(singleLine: '//', blockBegin: '/*', blockEnd: '*/'),
      importFormatter: (path) => "import '$path';",
      importIgnoredPrefixes: ['http:', 'https:', 'node:'],
      importPatterns: [
        // Matches: import ... from 'path' (ES Modules)
        RegExp(r'''from\s+['"]([^'"]+)['"]'''),
        // Matches: import 'path' (Side-effect imports)
        RegExp(r'''import\s+['"]([^'"]+)['"]'''),
        // Matches: require('path') (CommonJS style in TS)
        RegExp(r'''require\s*\(\s*['"]([^'"]+)['"]\s*\)'''),
      ],
    ),

    // --- PYTHON ---
    LanguageConfig(
      id: 'python',
      name: 'Python',
      extensions: {'py', 'pyw'},
      highlightMode: langPython,
      comments: const CommentConfig(singleLine: '#'),
      // Python imports are complex (dot notation), skipping simple path refactoring for now.
    ),

    // --- HTML ---
    LanguageConfig(
      id: 'html',
      name: 'HTML',
      extensions: {'html', 'htm', 'xhtml'},
      highlightMode: langXml,
      comments: const CommentConfig(blockBegin: '<!--', blockEnd: '-->'),
      importIgnoredPrefixes: ['http:', 'https:', '//', 'mailto:', 'tel:', 'javascript:'],
      importPatterns: [
        RegExp(r'''src=["']([^"']+)["']'''),
        RegExp(r'''href=["']([^"']+)["']'''),
      ],
    ),

    // --- CSS / SCSS ---
    LanguageConfig(
      id: 'css',
      name: 'CSS',
      extensions: {'css', 'scss', 'less'},
      highlightMode: langCss,
      comments: const CommentConfig(blockBegin: '/*', blockEnd: '*/'),
      importFormatter: (path) => "@import '$path';",
      importIgnoredPrefixes: ['http:', 'https:', 'data:'],
      importPatterns: [
        RegExp(r'''@import\s+["']([^"']+)["']'''),
        RegExp(r'''url\s*\(\s*["']?([^"')]+)["']?\s*\)'''),
      ],
    ),

    // --- C / C++ ---
    LanguageConfig(
      id: 'cpp',
      name: 'C++',
      extensions: {'cpp', 'c', 'cc', 'h', 'hpp'},
      highlightMode: langCpp,
      comments: const CommentConfig(singleLine: '//', blockBegin: '/*', blockEnd: '*/'),
      importFormatter: (path) => '#include "$path"',
      importPatterns: [
        RegExp(r'''#include\s+["']([^"']+)["']'''),
      ],
    ),

    // --- JAVA ---
    LanguageConfig(
      id: 'java',
      name: 'Java',
      extensions: {'java'},
      highlightMode: langJava,
      comments: const CommentConfig(singleLine: '//', blockBegin: '/*', blockEnd: '*/'),
    ),

    // --- KOTLIN ---
    LanguageConfig(
      id: 'kotlin',
      name: 'Kotlin',
      extensions: {'kt', 'kts'},
      highlightMode: langKotlin,
      comments: const CommentConfig(singleLine: '//', blockBegin: '/*', blockEnd: '*/'),
    ),

    // --- BASH / SHELL ---
    LanguageConfig(
      id: 'bash',
      name: 'Bash',
      extensions: {'sh', 'bash', 'zsh'},
      highlightMode: langBash,
      comments: const CommentConfig(singleLine: '#'),
    ),

    // --- JSON ---
    LanguageConfig(
      id: 'json',
      name: 'JSON',
      extensions: {'json', 'arb', 'ipynb'},
      highlightMode: langJson,
      // No standard comments in JSON
    ),

    // --- MARKDOWN ---
    LanguageConfig(
      id: 'markdown',
      name: 'Markdown',
      extensions: {'md', 'markdown'},
      highlightMode: langMarkdown,
      comments: const CommentConfig(singleLine: '>'), // Blockquote
      importPatterns: [
        // Standard link: [text](url)
        RegExp(r'''\]\(([^)]+)\)'''),
        // Image: ![alt](url)
        RegExp(r'''!\[.*?\]\(([^)]+)\)'''),
      ],
    ),

    // --- XML ---
    LanguageConfig(
      id: 'xml',
      name: 'XML',
      extensions: {'xml', 'xsd', 'svg', 'plist', 'manifest'},
      highlightMode: langXml,
      comments: const CommentConfig(blockBegin: '<!--', blockEnd: '-->'),
    ),

    // --- YAML ---
    LanguageConfig(
      id: 'yaml',
      name: 'YAML',
      extensions: {'yaml', 'yml'},
      highlightMode: langYaml,
      comments: const CommentConfig(singleLine: '#'),
    ),

    // --- LATEX ---
    LanguageConfig(
      id: 'latex',
      name: 'LaTeX',
      extensions: {'tex', 'sty', 'cls'},
      highlightMode: langLatex,
      comments: const CommentConfig(singleLine: '%'),
      importFormatter: (path) => '\\input{$path}',
      importPatterns: [
        RegExp(r'''\\input\{([^}]+)\}'''),
        RegExp(r'''\\include\{([^}]+)\}'''),
        RegExp(r'''\\includegraphics(?:\[.*\])?\{([^}]+)\}'''),
      ],
    ),

    // --- PROPERTIES ---
    LanguageConfig(
      id: 'properties',
      name: 'Properties',
      extensions: {'properties', 'conf', 'ini'},
      highlightMode: langProperties,
      comments: const CommentConfig(singleLine: '#'),
    ),
  ];
}