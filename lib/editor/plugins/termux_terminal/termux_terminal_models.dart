// FILE: lib/editor/plugins/termux_terminal/termux_terminal_models.dart

import 'package:flutter/material.dart';
import '../../models/editor_tab_models.dart';
import '../../models/editor_plugin_models.dart';

// Forward declaration for the widget state to be created in Phase 4
// In actual code, you would import 'termux_terminal_widget.dart'
abstract class TermuxTerminalWidgetState extends EditorWidgetState {}

@immutable
class TermuxTerminalTab extends EditorTab {
  @override
  final GlobalKey<TermuxTerminalWidgetState> editorKey;

  final String initialWorkingDirectory;
  final String? initialHistory;

  TermuxTerminalTab({
    required super.plugin,
    required this.initialWorkingDirectory,
    this.initialHistory,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<TermuxTerminalWidgetState>();

  @override
  void dispose() {
    // Cleanup socket connections if referenced here later
  }
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