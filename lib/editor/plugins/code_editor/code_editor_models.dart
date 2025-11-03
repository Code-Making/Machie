// =========================================
// FILE: lib/editor/plugins/code_editor/code_editor_models.dart
// =========================================

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import '../../editor_tab_models.dart';
import '../plugin_models.dart';
import 'code_editor_widgets.dart';

@immutable
class CodeEditorTab extends EditorTab {
  @override
  final GlobalKey<CodeEditorMachineState> editorKey;

  final String initialContent;
  final String? cachedContent;
  final String? initialLanguageKey;
  final String? initialBaseContentHash;

  CodeEditorTab({
    required super.plugin,
    required this.initialContent,
    this.cachedContent,
    this.initialLanguageKey,
    this.initialBaseContentHash,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<CodeEditorMachineState>();

  @override
  void dispose() {}

  Map<String, dynamic> toJson() => {
    'type': 'code',
    'id': id,
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
