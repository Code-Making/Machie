import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

import '../../models/editor_plugin_models.dart';
import '../../models/editor_tab_models.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/file_handler/file_handler.dart';
import 'markdown_editor_models.dart';
import 'markdown_editor_hot_state.dart';
import 'markdown_editor_widget.dart'; // We will define the stub for this next

class MarkdownEditorPlugin extends EditorPlugin {
  @override
  String get id => 'com.machine.markdown_editor';

  @override
  String get name => 'Markdown Pro';

  @override
  Widget get icon => const Icon(Icons.article_outlined);

  // Higher priority than CodeEditor (0) so this captures .md files first
  @override
  int get priority => 10; 

  @override
  PluginSettings? get settings => MarkdownEditorSettings();

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.toLowerCase().endsWith('.md') || 
           file.name.toLowerCase().endsWith('.markdown');
  }

  @override
  String? get hotStateDtoType => 'com.machine.markdown_state';

  @override
  Type? get hotStateDtoRuntimeType => MarkdownEditorHotStateDto;

  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => MarkdownEditorHotStateAdapter();

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    String bodyContent = '';
    MarkdownFrontMatter frontMatter = const MarkdownFrontMatter();
    Map<String, dynamic>? cachedJson;

    // 1. Check for Hot State (Restoring from background/crash)
    if (initData.hotState is MarkdownEditorHotStateDto) {
      final hotState = initData.hotState as MarkdownEditorHotStateDto;
      cachedJson = hotState.documentJson;
      // Re-parse the cached front matter string
      frontMatter = _parseFrontMatter(hotState.rawFrontMatter);
    } 
    // 2. Load from File System
    else if (initData.initialContent is EditorContentString) {
      final fullText = (initData.initialContent as EditorContentString).content;
      final parsed = _splitFrontMatter(fullText);
      
      frontMatter = parsed.frontMatter;
      bodyContent = parsed.body;
    }

    return MarkdownEditorTab(
      plugin: this,
      id: id,
      initialBodyContent: bodyContent,
      frontMatter: frontMatter,
      cachedDocumentJson: cachedJson,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return MarkdownEditorWidget(
      key: (tab as MarkdownEditorTab).editorKey,
      tab: tab,
    );
  }

  // --- Parsing Helpers ---

  /// Result object for the splitter
  ({MarkdownFrontMatter frontMatter, String body}) _splitFrontMatter(String text) {
    // Regex to find content between --- and --- at the start of the string
    // (?s) enables dotAll mode so . matches newlines
    final RegExp pattern = RegExp(r'^---\n(.*?)\n---\n', dotAll: true);
    final match = pattern.firstMatch(text);

    if (match != null) {
      final rawYamlString = match.group(1) ?? '';
      final frontMatter = _parseFrontMatter(rawYamlString);
      
      // Body is everything after the match
      final body = text.substring(match.end);
      return (frontMatter: frontMatter, body: body);
    }

    // No front matter found
    return (
      frontMatter: const MarkdownFrontMatter(), 
      body: text
    );
  }

  MarkdownFrontMatter _parseFrontMatter(String rawString) {
    try {
      if (rawString.trim().isEmpty) {
        return const MarkdownFrontMatter();
      }
      final yamlMap = loadYaml(rawString);
      if (yamlMap is Map) {
        return MarkdownFrontMatter(
          rawYaml: yamlMap,
          rawString: rawString,
        );
      }
    } catch (e) {
      debugPrint('Error parsing YAML front matter: $e');
    }
    return MarkdownFrontMatter(rawString: rawString);
  }
}