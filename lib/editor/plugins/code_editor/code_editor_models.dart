import 'package:flutter/material.dart';

import '../../models/editor_tab_models.dart';
import '../../models/text_editing_capability.dart';
import '../../models/editor_plugin_models.dart';
import 'code_editor_widgets.dart';

@immutable
class CodeEditorTab extends EditorTab {
  @override
  final GlobalKey<CodeEditorMachineState> editorKey;

  final String initialContent;
  final String? cachedContent;
  final String? initialLanguageId; 
  final String? initialBaseContentHash;

  CodeEditorTab({
    required super.plugin,
    required this.initialContent,
    this.cachedContent,
    this.initialLanguageId,
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

class CodeEditorSettings extends PluginSettings {
  bool wordWrap;
  double fontSize;
  String fontFamily;
  String themeName;
  double? fontHeight;
  bool fontLigatures;
  String scratchpadFilename;
  String? scratchpadLocalPath;

  CodeEditorSettings({
    this.wordWrap = false,
    this.fontSize = 14,
    this.fontFamily = 'JetBrainsMono',
    this.themeName = 'Atom One Dark',
    this.fontHeight,
    this.fontLigatures = true,
    this.scratchpadFilename = 'scratchpad.dart',
    this.scratchpadLocalPath,
  });

  @override
  Map<String, dynamic> toJson() => {
        'wordWrap': wordWrap,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'themeName': themeName,
        'fontHeight': fontHeight,
        'fontLigatures': fontLigatures,
        'scratchpadFilename': scratchpadFilename,
        'scratchpadLocalPath': scratchpadLocalPath,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    wordWrap = json['wordWrap'] ?? false;
    fontSize = json['fontSize']?.toDouble() ?? 14;
    fontFamily = json['fontFamily'] ?? 'JetBrainsMono';
    themeName = json['themeName'] ?? 'Atom One Dark';
    fontHeight = json['fontHeight']?.toDouble();
    fontLigatures = json['fontLigatures'] ?? true;
    scratchpadFilename = json['scratchpadFilename'] ?? 'scratchpad.dart';
    scratchpadLocalPath = json['scratchpadLocalPath'] as String?;
  }

  CodeEditorSettings copyWith({
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
    String? themeName,
    double? fontHeight,
    bool setFontHeightToNull = false,
    bool? fontLigatures,
    String? scratchpadFilename,
    String? scratchpadLocalPath,
    bool setScratchpadLocalPathToNull = false,
  }) {
    return CodeEditorSettings(
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      themeName: themeName ?? this.themeName,
      fontHeight: setFontHeightToNull ? null : (fontHeight ?? this.fontHeight),
      fontLigatures: fontLigatures ?? this.fontLigatures,
      scratchpadFilename: scratchpadFilename ?? this.scratchpadFilename,
      scratchpadLocalPath: setScratchpadLocalPathToNull
          ? null
          : (scratchpadLocalPath ?? this.scratchpadLocalPath),
    );
  }

  @override
  MachineSettings clone() {
    return CodeEditorSettings(
      wordWrap: wordWrap,
      fontSize: fontSize,
      fontFamily: fontFamily,
      themeName: themeName,
      fontHeight: fontHeight,
      fontLigatures: fontLigatures,
      scratchpadFilename: scratchpadFilename,
      scratchpadLocalPath: scratchpadLocalPath,
    );
  }
}

@immutable
class CodeEditorCommandContext extends TextEditableCommandContext {
  final bool canUndo;
  final bool canRedo;
  final bool hasMark;

  const CodeEditorCommandContext({
    this.canUndo = false,
    this.canRedo = false,
    this.hasMark = false,
    required super.hasSelection,
    super.appBarOverride,
    super.appBarOverrideKey,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CodeEditorCommandContext &&
        other.canUndo == canUndo &&
        other.canRedo == canRedo &&
        other.hasMark == hasMark &&
        super == other;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, canUndo, canRedo, hasMark);
}
