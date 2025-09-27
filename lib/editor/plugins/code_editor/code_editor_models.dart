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
    required super.plugin,
    required this.initialContent,
    super.id, // ADDED
  });

  @override
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
  double? fontHeight; // <-- ADDED

  CodeEditorSettings({
    this.wordWrap = false,
    this.fontSize = 14,
    this.fontFamily = 'JetBrainsMono',
    this.themeName = 'Atom One Dark',
    this.fontHeight, // <-- ADDED
  });

  @override
  Map<String, dynamic> toJson() => {
    'wordWrap': wordWrap,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'themeName': themeName,
    'fontHeight': fontHeight, // <-- ADDED
  };

  @override
  void fromJson(Map<String, dynamic> json) {
    wordWrap = json['wordWrap'] ?? false;
    fontSize = json['fontSize']?.toDouble() ?? 14;
    fontFamily = json['fontFamily'] ?? 'JetBrainsMono';
    themeName = json['themeName'] ?? 'Atom One Dark';
    fontHeight =
        json['fontHeight']
            ?.toDouble(); // <-- ADDED (will be null if not present)
  }

  CodeEditorSettings copyWith({
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
    String? themeName,
    double? fontHeight, // <-- ADDED
    bool setFontHeightToNull = false, // <-- ADDED special flag
  }) {
    return CodeEditorSettings(
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      themeName: themeName ?? this.themeName,
      // If the special flag is set, force fontHeight to be null.
      // Otherwise, use the provided value or the existing one.
      fontHeight:
          setFontHeightToNull
              ? null
              : (fontHeight ?? this.fontHeight), // <-- ADDED
    );
  }
}
