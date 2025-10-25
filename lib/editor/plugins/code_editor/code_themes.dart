// lib/plugins/code_editor/code_themes.dart

import 'package:flutter/material.dart'; // For TextStyle
import 'package:re_editor/re_editor.dart'; // For CodeHighlightThemeMode
import 'package:re_highlight/re_highlight.dart';

// IMPORTS FOR ALL THEMES
import 'package:re_highlight/styles/agate.dart';
import 'package:re_highlight/styles/an-old-hope.dart';
import 'package:re_highlight/styles/androidstudio.dart';
import 'package:re_highlight/styles/arduino-light.dart';
import 'package:re_highlight/styles/arta.dart';
import 'package:re_highlight/styles/ascetic.dart';
import 'package:re_highlight/styles/atom-one-dark-reasonable.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:re_highlight/styles/brown-paper.dart';
import 'package:re_highlight/styles/codepen-embed.dart';
import 'package:re_highlight/styles/color-brewer.dart';
import 'package:re_highlight/styles/dark.dart';
import 'package:re_highlight/styles/default.dart';
import 'package:re_highlight/styles/devibeans.dart';
import 'package:re_highlight/styles/docco.dart';
import 'package:re_highlight/styles/far.dart';
import 'package:re_highlight/styles/felipec.dart';
import 'package:re_highlight/styles/foundation.dart';
import 'package:re_highlight/styles/github-dark-dimmed.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';
import 'package:re_highlight/styles/gml.dart';
import 'package:re_highlight/styles/googlecode.dart';
import 'package:re_highlight/styles/gradient-dark.dart';
import 'package:re_highlight/styles/gradient-light.dart';
import 'package:re_highlight/styles/grayscale.dart';
import 'package:re_highlight/styles/hybrid.dart';
import 'package:re_highlight/styles/idea.dart';
import 'package:re_highlight/styles/intellij-light.dart';
import 'package:re_highlight/styles/ir-black.dart';
import 'package:re_highlight/styles/isbl-editor-dark.dart';
import 'package:re_highlight/styles/isbl-editor-light.dart';
import 'package:re_highlight/styles/kimbie-dark.dart';
import 'package:re_highlight/styles/kimbie-light.dart';
import 'package:re_highlight/styles/lightfair.dart';
import 'package:re_highlight/styles/lioshi.dart';
import 'package:re_highlight/styles/magula.dart';
import 'package:re_highlight/styles/mono-blue.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:re_highlight/styles/monokai.dart';
import 'package:re_highlight/styles/night-owl.dart';
import 'package:re_highlight/styles/nnfx-dark.dart';
import 'package:re_highlight/styles/nnfx-light.dart';
import 'package:re_highlight/styles/nord.dart';
import 'package:re_highlight/styles/obsidian.dart';
import 'package:re_highlight/styles/panda-syntax-dark.dart';
import 'package:re_highlight/styles/panda-syntax-light.dart';
import 'package:re_highlight/styles/paraiso-dark.dart';
import 'package:re_highlight/styles/paraiso-light.dart';
import 'package:re_highlight/styles/pojoaque.dart';
import 'package:re_highlight/styles/purebasic.dart';
import 'package:re_highlight/styles/qtcreator-dark.dart';
import 'package:re_highlight/styles/qtcreator-light.dart';
import 'package:re_highlight/styles/rainbow.dart';
import 'package:re_highlight/styles/routeros.dart';
import 'package:re_highlight/styles/school-book.dart';
import 'package:re_highlight/styles/shades-of-purple.dart';
import 'package:re_highlight/styles/srcery.dart';
import 'package:re_highlight/styles/stackoverflow-dark.dart';
import 'package:re_highlight/styles/stackoverflow-light.dart';
import 'package:re_highlight/styles/sunburst.dart';
import 'package:re_highlight/styles/tokyo-night-dark.dart';
import 'package:re_highlight/styles/tokyo-night-light.dart';
import 'package:re_highlight/styles/tomorrow-night-blue.dart';
import 'package:re_highlight/styles/tomorrow-night-bright.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:re_highlight/styles/xcode.dart';
import 'package:re_highlight/styles/xt256.dart';

// IMPORTS FOR LANGUAGES (from previous step, still needed for languageNameToModeMap)
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

class CodeThemes {

// NEW: Add the custom rainbow styles.
  static const Map<String, TextStyle> rainbowStyles = {
    'rainbow-bracket-depth-0': TextStyle(color: Color(0xFFE06C75)), // Red
    'rainbow-bracket-depth-1': TextStyle(color: Color(0xFFE5C07B)), // Yellow
    'rainbow-bracket-depth-2': TextStyle(color: Color(0xFF61AFEF)), // Blue
    'rainbow-bracket-depth-3': TextStyle(color: Color(0xFFC678DD)), // Purple
    'rainbow-bracket-depth-4': TextStyle(color: Color(0xFF98C379)), // Green
    'rainbow-bracket-depth-5': TextStyle(color: Color(0xFF56B6C2)), // Cyan
  };
  // Define available code themes as a map of theme names to their highlight maps
  static final Map<String, Map<String, TextStyle>> availableCodeThemes = {
    // Manually add Atom One Dark as a default, then auto-generate the rest.
    // Ensure the key matches the default theme name in CodeEditorSettings.
    'Atom One Dark': atomOneDarkTheme,

    // GENERATED LIST OF THEMES:    'A11y Dark': a11yDarkTheme,
    'Agate': agateTheme,
    'An Old Hope': anOldHopeTheme,
    'Android Studio': androidstudioTheme,
    'Arduino Light': arduinoLightTheme,
    'Arta': artaTheme,
    'Ascetic': asceticTheme,
    'Atom One Dark Reasonable': atomOneDarkReasonableTheme,
    'Atom One Light': atomOneLightTheme,
    'Brown Paper': brownPaperTheme,
    'CodePen Embed': codepenEmbedTheme,
    'Color Brewer': colorBrewerTheme,
    'Dark': darkTheme, // Note: This clashes with Flutter's ThemeData.dark()
    'Default': defaultTheme,
    'Devibeans': devibeansTheme,
    'Docco': doccoTheme,
    'Far': farTheme,
    'Felipec': felipecTheme,
    'Foundation': foundationTheme,
    'GitHub Dark Dimmed': githubDarkDimmedTheme,
    'GitHub Dark': githubDarkTheme,
    'GitHub': githubTheme,
    'GML': gmlTheme,
    'Google Code': googlecodeTheme,
    'Gradient Dark': gradientDarkTheme,
    'Gradient Light': gradientLightTheme,
    'Grayscale': grayscaleTheme,
    'Hybrid': hybridTheme,
    'Idea': ideaTheme,
    'IntelliJ Light': intellijLightTheme,
    'IR Black': irBlackTheme,
    'ISBL Editor Dark': isblEditorDarkTheme,
    'ISBL Editor Light': isblEditorLightTheme,
    'Kimbie Dark': kimbieDarkTheme,
    'Kimbie Light': kimbieLightTheme,
    'Lightfair': lightfairTheme,
    'Lioshi': lioshiTheme,
    'Magula': magulaTheme,
    'Mono Blue': monoBlueTheme,
    'Monokai Sublime': monokaiSublimeTheme,
    'Monokai': monokaiTheme,
    'Night Owl': nightOwlTheme,
    'NNFX Dark': nnfxDarkTheme,
    'NNFX Light': nnfxLightTheme,
    'Nord': nordTheme,
    'Obsidian': obsidianTheme,
    'Panda Syntax Dark': pandaSyntaxDarkTheme,
    'Panda Syntax Light': pandaSyntaxLightTheme,
    'Paraiso Dark': paraisoDarkTheme,
    'Paraiso Light': paraisoLightTheme,
    'Pojoaque': pojoaqueTheme,
    'PureBasic': purebasicTheme,
    'QtCreator Dark': qtcreatorDarkTheme,
    'QtCreator Light': qtcreatorLightTheme,
    'Rainbow': rainbowTheme,
    'RouterOS': routerosTheme,
    'School Book': schoolBookTheme,
    'Shades of Purple': shadesOfPurpleTheme,
    'Srcery': srceryTheme,
    'StackOverflow Dark': stackoverflowDarkTheme,
    'StackOverflow Light': stackoverflowLightTheme,
    'Sunburst': sunburstTheme,
    'Tokyo Night Dark': tokyoNightDarkTheme,
    'Tokyo Night Light': tokyoNightLightTheme,
    'Tomorrow Night Blue': tomorrowNightBlueTheme,
    'Tomorrow Night Bright': tomorrowNightBrightTheme,
    'VS': vsTheme,
    'VS2015': vs2015Theme,
    'Xcode': xcodeTheme,
    'XT256': xt256Theme,
  };

  // Map of language keys to their highlight modes (as before)
  static final Map<String, dynamic> languageNameToModeMap = {
    'dart': langDart,
    'python': langPython,
    'javascript': langJavascript,
    'typescript': langTypescript,
    'java': langJava,
    'cpp': langCpp,
    'latex': langLatex,
    'css': langCss,
    'json': langJson,
    'yaml': langYaml,
    'markdown': langMarkdown,
    'kotlin': langKotlin,
    'bash': langBash,
    'xml': langXml,
    'plaintext': langPlaintext,
    'properties': langProperties,
  };

  // Map of file extensions to their corresponding language names (as before)
  static const Map<String, String> languageExtToNameMap = {
    'dart': 'dart',
    'js': 'javascript',
    'jsx': 'javascript',
    'mjs': 'javascript',
    'npmrc': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'java': 'java',
    'cpp': 'cpp',
    'cc': 'cpp',
    'h': 'cpp',
    'css': 'css',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'json': 'json',
    'htm': 'xml',
    'html': 'xml',
    'xml': 'xml',
    'yaml': 'yaml',
    'yml': 'yaml',
    'md': 'markdown',
    'sh': 'bash',
    'tex': 'latex',
    'gitignore': 'plaintext',
    'txt': 'plaintext',
    'properties' : 'properties',
  };

  static String inferLanguageKey(String uri) {
    final ext = uri.split('.').last.toLowerCase();
    return languageExtToNameMap[ext] ?? 'plaintext';
  }

  static Map<String, CodeHighlightThemeMode> getHighlightThemeMode(
    String? langKey, {
    bool enableRainbowBrackets = false, // Default to false
}) {
  final effectiveLangKey = langKey ?? 'plaintext';
  final Mode? originalMode = languageNameToModeMap[effectiveLangKey];
  
  if (originalMode == null) {
    return {'plaintext': CodeHighlightThemeMode(mode: langPlaintext)};
  }
  
  if (!enableRainbowBrackets) {
    return {effectiveLangKey: CodeHighlightThemeMode(mode: originalMode)};
  }
  
  // Call the robust merger.
  final Mode mergedMode = _mergeGrammars(originalMode);
  
  final String rainbowLangKey = '$effectiveLangKey-rainbow';
  return {rainbowLangKey: CodeHighlightThemeMode(mode: mergedMode)};
}

  static String formatLanguageName(String key) {
    if (key == 'cpp') return 'C++';
    if (key == 'javascript') return 'JavaScript';
    if (key == 'typescript') return 'TypeScript';
    if (key == 'markdown') return 'Markdown';
    if (key == 'kotlin') return 'Kotlin';
    return key[0].toUpperCase() + key.substring(1);
  }
}

// --- Place these utility functions at the top level of your file ---

/// Recursively copies a Mode object, allowing for modifications.
Mode _cloneMode(Mode original, {List<Mode>? contains, Map<String, Mode>? refs}) {
  return Mode(
    aliases: original.aliases,
    begin: original.begin,
    beginKeywords: original.beginKeywords,
    cachedVariants: original.cachedVariants,
    caseInsensitive: original.caseInsensitive,
    className: original.className,
    end: original.end,
    endSameAsBegin: original.endSameAsBegin,
    endsWithParent: original.endsWithParent,
    excludeBegin: original.excludeBegin,
    excludeEnd: original.excludeEnd,
    illegal: original.illegal,
    keywords: original.keywords,
    lexemes: original.lexemes,
    parent: original.parent,
    relevance: original.relevance,
    returnBegin: original.returnBegin,
    returnEnd: original.returnEnd,
    scope: original.scope,
    skip: original.skip,
    starts: original.starts,
    subLanguage: original.subLanguage,
    variants: original.variants,
    contains: contains ?? original.contains,
    refs: refs ?? original.refs,
    // --- Specific properties for beginScope/endScope ---
    beginScope: original.beginScope,
    endScope: original.endScope,
  );
}

List<Mode> _createRainbowRules({int depth = 0, int maxDepth = 6}) {
  if (depth >= maxDepth) {
    return [];
  }
  final String scopeName = 'rainbow-bracket-depth-$depth';
  
  // CRITICAL: The 'contains' list for a rainbow rule should only contain
  // the rules for the *next level* of rainbow brackets.
  // It no longer needs to contain the original language rules.
  final List<Mode> nestedRules = _createRainbowRules(depth: depth + 1, maxDepth: maxDepth);

  return [
    Mode(
      begin: r'\{', end: r'\}',
      beginScope: scopeName, endScope: scopeName,
      contains: nestedRules, relevance: 0,
    ),
    Mode(
      begin: r'\(', end: r'\)',
      beginScope: scopeName, endScope: scopeName,
      contains: nestedRules, relevance: 0,
    ),
    Mode(
      begin: r'\[', end: r'\]',
      beginScope: scopeName, endScope: scopeName,
      contains: nestedRules, relevance: 0,
    ),
  ];
}

/// Merges a list of additive modes into a base language grammar.
Mode _mergeGrammars(Mode baseLanguage) {
  final Set<String> visitedRefs = {};
  final Map<String, Mode> newRefs = {};
  
  // Generate the complete, self-contained rainbow grammar once.
  final List<Mode> rainbowRules = _createRainbowRules();

  Mode _recursiveMerge(Mode currentMode) {
    if (currentMode.ref != null) {
      if (!visitedRefs.contains(currentMode.ref!)) {
        visitedRefs.add(currentMode.ref!);
        final Mode? originalRefMode = baseLanguage.refs?[currentMode.ref!];
        if (originalRefMode != null) {
          newRefs[currentMode.ref!] = _recursiveMerge(originalRefMode);
        }
      }
      return currentMode;
    }

    List<Mode> processedChildren = [];
    if (currentMode.contains != null) {
      for (final childMode in currentMode.contains!) {
        processedChildren.add(_recursiveMerge(childMode));
      }
    }

    // --- THE KEY CHANGE: APPEND INSTEAD OF PREPEND ---
    // The original rules run first. Our rainbow rules act as a fallback.
    final List<Mode> finalContains = [...processedChildren, ...rainbowRules];

    return _cloneMode(currentMode, contains: finalContains);
  }

  baseLanguage.refs?.forEach((key, mode) {
    if (!visitedRefs.contains(key)) {
      visitedRefs.add(key);
      newRefs[key] = _recursiveMerge(mode);
    }
  });

  final Mode mergedTopLevelMode = _recursiveMerge(baseLanguage);
  return _cloneMode(mergedTopLevelMode, refs: newRefs);
}

/// Recursively generates the nested modes for rainbow brackets.
List<Mode> _createRainbowBracketsModes({int depth = 0, int maxDepth = 6}) {
  if (depth >= maxDepth) {
    return [];
  }
  final String scope = 'rainbow-bracket-depth-$depth';
  final List<Mode> nestedModes = _createRainbowBracketsModes(depth: depth + 1, maxDepth: maxDepth);
  return [
    Mode(begin: r'\(', end: r'\)', scope: scope, contains: nestedModes, relevance: 0),
    Mode(begin: r'\[', end: r'\]', scope: scope, contains: nestedModes, relevance: 0),
    Mode(begin: r'\{', end: r'\}', scope: scope, contains: nestedModes, relevance: 0),
  ];
}