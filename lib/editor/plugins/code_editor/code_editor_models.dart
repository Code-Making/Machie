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
  final String? initialLanguageKey; // <-- ADDED: To pass cached key on creation
  
  CodeEditorTab({
    required super.plugin,
    required this.initialContent,
    this.initialLanguageKey, // <-- ADDED
    super.id, // ADDED
  });

  @override
  void dispose() {}

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
  double? fontHeight;
  bool fontLigatures; // <-- ADDED

  CodeEditorSettings({
    this.wordWrap = false,
    this.fontSize = 14,
    this.fontFamily = 'JetBrainsMono',
    this.themeName = 'Atom One Dark',
    this.fontHeight,
    this.fontLigatures = true, // <-- ADDED (default to enabled)
  });

  @override
  Map<String, dynamic> toJson() => {
    'wordWrap': wordWrap,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'themeName': themeName,
    'fontHeight': fontHeight,
    'fontLigatures': fontLigatures, // <-- ADDED
  };

  @override
  void fromJson(Map<String, dynamic> json) {
    wordWrap = json['wordWrap'] ?? false;
    fontSize = json['fontSize']?.toDouble() ?? 14;
    fontFamily = json['fontFamily'] ?? 'JetBrainsMono';
    themeName = json['themeName'] ?? 'Atom One Dark';
    fontHeight = json['fontHeight']?.toDouble();
    fontLigatures = json['fontLigatures'] ?? true; // <-- ADDED
  }

  CodeEditorSettings copyWith({
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
    String? themeName,
    double? fontHeight,
    bool setFontHeightToNull = false,
    bool? fontLigatures, // <-- ADDED
  }) {
    return CodeEditorSettings(
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      themeName: themeName ?? this.themeName,
      fontHeight: setFontHeightToNull ? null : (fontHeight ?? this.fontHeight),
      fontLigatures: fontLigatures ?? this.fontLigatures, // <-- ADDED
    );
  }
}
