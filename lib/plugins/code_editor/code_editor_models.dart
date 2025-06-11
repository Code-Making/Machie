import 'package:re_editor/re_editor.dart';
import 'package:flutter/material.dart';

import '../plugin_models.dart';
import '../../session/session_models.dart';
import '../../data/file_handler/file_handler.dart';

immutable
class CodeEditorTab extends EditorTab {
  final CodeLineEditingController controller;
  final CodeCommentFormatter commentFormatter;
  final String? languageKey;

  // MODIFIED: Constructor signature updated to match superclass. 'const' is preserved.
  const CodeEditorTab({
    required super.file,
    required this.controller,
    required super.plugin,
    required this.commentFormatter,
    super.isDirty = false,
    this.languageKey,
  });

  @override
  void dispose() => controller.dispose();
  @override
  String get contentString => controller.text;

  @override
  CodeEditorTab copyWith({
    DocumentFile? file,
    EditorPlugin? plugin,
    bool? isDirty,
    CodeLineEditingController? controller,
    CodeCommentFormatter? commentFormatter,
    String? languageKey,
  }) {
    return CodeEditorTab(
      file: file ?? this.file,
      plugin: plugin ?? this.plugin,
      isDirty: isDirty ?? this.isDirty,
      controller: controller ?? this.controller,
      commentFormatter: commentFormatter ?? this.commentFormatter,
      languageKey: languageKey ?? this.languageKey,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'code',
    'fileUri': file.uri,
    'pluginType': plugin.runtimeType.toString(),
    'languageKey': languageKey,
    'isDirty': isDirty,
  };
}

// --------------------
//  Code Editor Settings
// --------------------
class CodeEditorSettings extends PluginSettings {
  bool wordWrap;
  double fontSize;
  String fontFamily;
  String themeName; // NEW: Added theme name

  CodeEditorSettings({
    this.wordWrap = false,
    this.fontSize = 14,
    this.fontFamily = 'JetBrainsMono',
    this.themeName = 'Atom One Dark', // NEW: Default theme
  });

  @override
  Map<String, dynamic> toJson() => {
    'wordWrap': wordWrap,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'themeName': themeName, // NEW: Serialize themeName
  };

  @override
  void fromJson(Map<String, dynamic> json) {
    wordWrap = json['wordWrap'] ?? false;
    fontSize = json['fontSize']?.toDouble() ?? 14;
    fontFamily = json['fontFamily'] ?? 'JetBrainsMono';
    themeName =
        json['themeName'] ?? 'Atom One Dark'; // NEW: Deserialize themeName
  }

  CodeEditorSettings copyWith({
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
    String? themeName, // NEW: copyWith themeName
  }) {
    return CodeEditorSettings(
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      themeName: themeName ?? this.themeName, // NEW: copyWith themeName
    );
  }
}
