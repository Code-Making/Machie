// FILE: lib/editor/plugins/termux_terminal/termux_terminal_models.dart

import 'package:flutter/material.dart';
import '../../models/editor_tab_models.dart';
import '../../models/editor_plugin_models.dart';
import 'widgets/termux_terminal_widget.dart'; // Import the widget file to get the API class

// The abstract state class is removed from here to prevent type conflicts.
// The API contract is now defined solely in the widget file.

@immutable
class TermuxTerminalTab extends EditorTab {
  @override
  final GlobalKey<TermuxTerminalWidgetApi> editorKey; // Updated to use the correct API key type

  final String initialWorkingDirectory;
  final String? initialHistory;

  TermuxTerminalTab({
    required super.plugin,
    required this.initialWorkingDirectory,
    this.initialHistory,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<TermuxTerminalWidgetApi>();

  @override
  void dispose() {}
}

class TermuxTerminalSettings extends PluginSettings {
  double fontSize;
  String fontFamily;
  String termuxWorkDir;
  String shellCommand;
  bool useDarkTheme;

  TermuxTerminalSettings({
    this.fontSize = 14.0,
    this.fontFamily = 'JetBrainsMono',
    this.termuxWorkDir = '/data/data/com.termux/files/home',
    this.shellCommand = 'bash',
    this.useDarkTheme = true,
  });

  @override
  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'termuxWorkDir': termuxWorkDir,
        'shellCommand': shellCommand,
        'useDarkTheme': useDarkTheme,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    fontSize = (json['fontSize'] as num?)?.toDouble() ?? 14.0;
    fontFamily = json['fontFamily'] as String? ?? 'JetBrainsMono';
    termuxWorkDir = json['termuxWorkDir'] as String? ?? '/data/data/com.termux/files/home';
    shellCommand = json['shellCommand'] as String? ?? 'bash';
    useDarkTheme = json['useDarkTheme'] as bool? ?? true;
  }

  TermuxTerminalSettings copyWith({
    double? fontSize,
    String? fontFamily,
    String? termuxWorkDir,
    String? shellCommand,
    bool? useDarkTheme,
  }) {
    return TermuxTerminalSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      termuxWorkDir: termuxWorkDir ?? this.termuxWorkDir,
      shellCommand: shellCommand ?? this.shellCommand,
      useDarkTheme: useDarkTheme ?? this.useDarkTheme,
    );
  }

  @override
  MachineSettings clone() {
    return copyWith();
  }
}