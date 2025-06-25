// =========================================
// FILE: lib/editor/plugins/code_editor/code_editor_models.dart
// =========================================

// lib/editor/plugins/code_editor/code_editor_models.dart
import 'package:flutter/material.dart';
import '../plugin_models.dart';
import '../../editor_tab_models.dart';
// import '../../../data/file_handler/file_handler.dart'; // REMOVED

@immutable
class CodeEditorTab extends EditorTab {
  final String initialContent;

  CodeEditorTab({
    // REMOVED: super.file,
    required super.plugin,
    required this.initialContent,
  });

  @override
  void dispose() {}

  @override
  CodeEditorTab copyWith({
    // REMOVED: DocumentFile? file,
    EditorPlugin? plugin,
    String? initialContent,
  }) {
    // A new tab gets a new ID and key automatically from the super constructor.
    return CodeEditorTab(
      // REMOVED: file: file ?? this.file,
      plugin: plugin ?? this.plugin,
      initialContent: initialContent ?? this.initialContent,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'code',
    'id': id, // Serialize the stable ID
    'pluginType': plugin.runtimeType.toString(),
  };
}

// ... CodeEditorSettings is unchanged ...
class CodeEditorSettings extends PluginSettings {
  bool wordWrap;
  double fontSize;
  String fontFamily;
  String themeName;
  CodeEditorSettings({
    this.wordWrap = false,
    this.fontSize = 14,
    this.fontFamily = 'JetBrainsMono',
    this.themeName = 'Atom One Dark',
  });
  @override
  Map<String, dynamic> toJson() => {
    'wordWrap': wordWrap,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'themeName': themeName,
  };
  @override
  void fromJson(Map<String, dynamic> json) {
    wordWrap = json['wordWrap'] ?? false;
    fontSize = json['fontSize']?.toDouble() ?? 14;
    fontFamily = json['fontFamily'] ?? 'JetBrainsMono';
    themeName = json['themeName'] ?? 'Atom One Dark';
  }

  CodeEditorSettings copyWith({
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
    String? themeName,
  }) {
    return CodeEditorSettings(
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      themeName: themeName ?? this.themeName,
    );
  }
}