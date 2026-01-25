import 'package:flutter/material.dart';
import '../../models/editor_tab_models.dart';
import '../../models/editor_plugin_models.dart';
import 'markdown_editor_widget.dart';

@immutable
class MarkdownFrontMatter {
  final Map<dynamic, dynamic> rawYaml;
  final String rawString; // The actual string between --- and ---

  const MarkdownFrontMatter({
    this.rawYaml = const {},
    this.rawString = '',
  });

  String? get bannerUrl => rawYaml['banner'] as String?;
  String? get description => rawYaml['description'] as String?;
  List<String> get tags {
    final t = rawYaml['tags'];
    if (t is List) return t.map((e) => e.toString()).toList();
    return [];
  }
}

@immutable
class MarkdownEditorTab extends EditorTab {
  @override
  final GlobalKey<MarkdownEditorWidgetState> editorKey;

  /// The raw markdown content EXCLUDING the front matter
  final String initialBodyContent;
  
  /// The parsed front matter data
  final MarkdownFrontMatter frontMatter;
  
  /// If we are restoring from hot state, this contains the AppFlowy Document JSON
  final Map<String, dynamic>? cachedDocumentJson;

  MarkdownEditorTab({
    required super.plugin,
    required this.initialBodyContent,
    required this.frontMatter,
    this.cachedDocumentJson,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<MarkdownEditorWidgetState>();

  @override
  void dispose() {}
}

class MarkdownEditorSettings extends PluginSettings {
  bool readOnly;
  bool showBanner;

  MarkdownEditorSettings({
    this.readOnly = false,
    this.showBanner = true,
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    readOnly = json['readOnly'] ?? false;
    showBanner = json['showBanner'] ?? true;
  }

  @override
  Map<String, dynamic> toJson() => {
        'readOnly': readOnly,
        'showBanner': showBanner,
      };

  @override
  MachineSettings clone() {
    return MarkdownEditorSettings(
      readOnly: readOnly,
      showBanner: showBanner,
    );
  }
}