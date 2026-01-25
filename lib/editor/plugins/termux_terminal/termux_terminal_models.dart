import 'package:collection/collection.dart'; // Import for ListEquality
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
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalShortcut &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          command == other.command &&
          iconName == other.iconName;

  @override
  int get hashCode => Object.hash(label, command, iconName);
}

class TermuxTerminalSettings extends PluginSettings {
  final double fontSize;
  final String fontFamily;
  final String termuxWorkDir;
  final String shellCommand;
  final bool useDarkTheme;
  final List<TerminalShortcut> customShortcuts;

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
    // Note: Since fields are final, fromJson is technically "unused" in 
    // the immutable pattern used by SettingsNotifier if it reconstructs 
    // the object. However, we implement it for compatibility if needed.
    // The SettingsNotifier actually relies on the initial constructor 
    // and then calls copyWith or re-instantiation.
  }

  // Factory used by SettingsNotifier deserialization logic
  // (Assuming you updated the generic logic to use constructors/factories 
  // or that this class is mutable in your specific Settings implementation.
  // Since I made fields final for safety, here is the helper).
  factory TermuxTerminalSettings.fromJson(Map<String, dynamic> json) {
    return TermuxTerminalSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      fontFamily: json['fontFamily'] as String? ?? 'JetBrainsMono',
      termuxWorkDir: json['termuxWorkDir'] as String? ?? '/data/data/com.termux/files/home',
      shellCommand: json['shellCommand'] as String? ?? 'bash',
      useDarkTheme: json['useDarkTheme'] as bool? ?? true,
      customShortcuts: json['customShortcuts'] != null
          ? (json['customShortcuts'] as List)
              .map((e) => TerminalShortcut.fromJson(e as Map<String, dynamic>))
              .toList()
          : _defaultShortcuts(),
    );
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
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TermuxTerminalSettings &&
          runtimeType == other.runtimeType &&
          fontSize == other.fontSize &&
          fontFamily == other.fontFamily &&
          termuxWorkDir == other.termuxWorkDir &&
          shellCommand == other.shellCommand &&
          useDarkTheme == other.useDarkTheme &&
          const ListEquality().equals(customShortcuts, other.customShortcuts);

  @override
  int get hashCode => Object.hash(
        fontSize,
        fontFamily,
        termuxWorkDir,
        shellCommand,
        useDarkTheme,
        const ListEquality().hash(customShortcuts),
      );
}