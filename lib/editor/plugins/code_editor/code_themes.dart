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
    String? langKey,
  ) {
    final effectiveLangKey = langKey ?? 'plaintext';
    final mode = languageNameToModeMap[effectiveLangKey];
    if (mode != null) {
      return {effectiveLangKey: CodeHighlightThemeMode(mode: mode)};
    }
    return {'plaintext': CodeHighlightThemeMode(mode: langPlaintext)};
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

/// A plugin for re_highlight that colors bracket pairs in a cycling sequence
/// of colors, creating a "rainbow" effect.
///
/// It uses existing, common theme scopes to ensure that the bracket colors
/// are always consistent with the currently active theme.
class RainbowBracketsPlugin extends HLPlugin {
  /// A list of common scope names that are likely to have distinct and
  /// visually pleasing colors in most themes. The colors will cycle through this list.
  final List<String> _scopes = const [
    'keyword',
    'built_in',
    'title.class_',
    'string',
    'number',
  ];

  /// Defines the matching pairs for opening and closing brackets.
  final Map<String, String> _bracketPairs = const {
    '(': ')',
    '[': ']',
    '{': '}',
  };

  /// This hook is called before the main highlighting process. We don't need
  /// to do anything here, so we provide an empty implementation.
  @override
  void beforeHighlight(BeforeHighlightContext context) {}

  /// This hook is called after the main highlighting process is complete.
  /// We will traverse the resulting node tree and apply our bracket colors.
  @override
  void afterHighlight(HighlightResult result) {
    // The emitter's root node contains the list of all top-level nodes.
    final rootChildren = result.emitter.rootNode.children;
    if (rootChildren == null) {
      return;
    }

    // Start the recursive processing and replace the root's children with the new list.
    result.emitter.rootNode.children = _processNodes(rootChildren, []);
  }

  /// Recursively processes a list of DataNodes to apply bracket coloring.
  /// A stack is passed down to keep track of the current nesting depth.
  List<DataNode> _processNodes(List<DataNode> nodes, List<String> bracketStack) {
    final List<DataNode> newNodes = [];

    for (final node in nodes) {
      // If the node is already styled (has a scope), we add it as-is and
      // do not process it further. This prevents coloring brackets in strings, comments, etc.
      if (node.scope != null) {
        newNodes.add(node);
        continue;
      }
      
      // If a node has children, it's a container. Recurse into it.
      if (node.children != null) {
        final processedChildren = _processNodes(node.children!, bracketStack);
        newNodes.add(DataNode(children: processedChildren));
        continue;
      }
      
      // If a node has a value, it's a leaf node containing plain text.
      // This is where we will find and color the brackets.
      if (node.value != null) {
        final text = node.value!;
        int lastIndex = 0;
        
        for (int i = 0; i < text.length; i++) {
          final char = text[i];
          
          // --- Handle Opening Brackets ---
          if (_bracketPairs.containsKey(char)) {
            if (i > lastIndex) {
              newNodes.add(DataNode(value: text.substring(lastIndex, i)));
            }
            final scope = _scopes[bracketStack.length % _scopes.length];
            newNodes.add(DataNode(scope: scope, value: char));
            bracketStack.add(char);
            lastIndex = i + 1;
          }
          // --- Handle Closing Brackets ---
          else if (_bracketPairs.containsValue(char)) {
            if (bracketStack.isNotEmpty && _bracketPairs[bracketStack.last] == char) {
              if (i > lastIndex) {
                newNodes.add(DataNode(value: text.substring(lastIndex, i)));
              }
              bracketStack.removeLast();
              final scope = _scopes[bracketStack.length % _scopes.length];
              newNodes.add(DataNode(scope: scope, value: char));
              lastIndex = i + 1;
            }
          }
        }
        
        if (lastIndex < text.length) {
          newNodes.add(DataNode(value: text.substring(lastIndex)));
        }
      }
    }
    
    return newNodes;
  }
}
