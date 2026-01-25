import 'package:flutter/material.dart';
import '../../models/editor_tab_models.dart';
import '../../models/editor_plugin_models.dart';
import 'widgets/termux_terminal_widget.dart';

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
  void dispose() {}
}

class TerminalShortcut {
  final String label;
  final String command;
  final String iconName;

  const TerminalShortcut({
    required this.label,
    required this.command,
    this.iconName = 'code',
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'command': command,
        'iconName': iconName,
      };

  factory TerminalShortcut.fromJson(Map<String, dynamic> json) {
    return TerminalShortcut(
      label: json['label'] as String,
      command: json['command'] as String,
      iconName: json['iconName'] as String? ?? 'code',
    );
  }

  // Helper to map string names to IconData.
  // This duplicates the list in the Settings Widget slightly for safety,
  // but ensures the Plugin doesn't depend on the UI widget file.
  static IconData resolveIcon(String name) {
    const map = {
      'terminal': Icons.terminal,
      'play': Icons.play_arrow,
      'stop': Icons.stop,
      'refresh': Icons.refresh,
      'git': Icons.commit,
      'folder': Icons.folder_open,
      'list': Icons.list,
      'build': Icons.build,
      'debug': Icons.bug_report,
      'upload': Icons.upload,
      'download': Icons.download,
      'delete': Icons.delete_outline,
      'save': Icons.save_outlined,
      'code': Icons.code,
      'settings': Icons.settings_outlined,
      'star': Icons.star_border,
      'flash': Icons.flash_on,
      'link': Icons.link,
    };
    return map[name] ?? Icons.code;
  }
}

class TermuxTerminalSettings extends PluginSettings {
  double fontSize;
  String fontFamily;
  String termuxWorkDir;
  String shellCommand;
  bool useDarkTheme;
  List<TerminalShortcut> customShortcuts;

  TermuxTerminalSettings({
    this.fontSize = 14.0,
    this.fontFamily = 'JetBrainsMono',
    this.termuxWorkDir = '/data/data/com.termux/files/home',
    this.shellCommand = 'bash',
    this.useDarkTheme = true,
    List<TerminalShortcut>? customShortcuts,
  }) : customShortcuts = customShortcuts ?? _defaultShortcuts();

  static List<TerminalShortcut> _defaultShortcuts() {
    return [
      const TerminalShortcut(
          label: 'Git Status', command: 'git status', iconName: 'git'),
      const TerminalShortcut(label: 'LS', command: 'ls -la', iconName: 'list'),
      const TerminalShortcut(
          label: 'Node', command: 'npm start', iconName: 'play'),
    ];
  }

  @override
  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'termuxWorkDir': termuxWorkDir,
        'shellCommand': shellCommand,
        'useDarkTheme': useDarkTheme,
        'customShortcuts': customShortcuts.map((e) => e.toJson()).toList(),
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    fontSize = (json['fontSize'] as num?)?.toDouble() ?? 14.0;
    fontFamily = json['fontFamily'] as String? ?? 'JetBrainsMono';
    termuxWorkDir = json['termuxWorkDir'] as String? ?? '/data/data/com.termux/files/home';
    shellCommand = json['shellCommand'] as String? ?? 'bash';
    useDarkTheme = json['useDarkTheme'] as bool? ?? true;

    if (json['customShortcuts'] != null) {
      customShortcuts = (json['customShortcuts'] as List)
          .map((e) => TerminalShortcut.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      customShortcuts = _defaultShortcuts();
    }
  }

  TermuxTerminalSettings copyWith({
    double? fontSize,
    String? fontFamily,
    String? termuxWorkDir,
    String? shellCommand,
    bool? useDarkTheme,
    List<TerminalShortcut>? customShortcuts,
  }) {
    return TermuxTerminalSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      termuxWorkDir: termuxWorkDir ?? this.termuxWorkDir,
      shellCommand: shellCommand ?? this.shellCommand,
      useDarkTheme: useDarkTheme ?? this.useDarkTheme,
      customShortcuts: customShortcuts ?? List.from(this.customShortcuts),
    );
  }

  @override
  MachineSettings clone() {
    return copyWith();
  }
}