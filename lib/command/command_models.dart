import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/file_handler/file_handler.dart';
import '../editor/models/editor_tab_models.dart';

import '../editor/plugins/editor_plugin_registry.dart'; 
import '../editor/tab_context_commands.dart'; 

final allTabContextCommandsProvider = Provider<List<TabContextCommand>>((ref) {
  final allPlugins = ref.watch(activePluginsProvider);

    final genericCommands = AppTabContextCommands.getCommands();

    final pluginCommands =
      allPlugins.expand((p) => p.getTabContextMenuCommands()).toList();

    return [...genericCommands, ...pluginCommands];
});

class CommandIcon {
  static const Map<String, IconData> availableIcons = {
    'folder': Icons.folder_outlined,
    'edit': Icons.edit_note_outlined,
    'build': Icons.build_outlined,
    'play': Icons.play_arrow_outlined,
    'debug': Icons.bug_report_outlined,
    'star': Icons.star_border,
    'code': Icons.code,
    'settings': Icons.settings_outlined,
    'web': Icons.public,
  };

  static Widget getIcon(String? name) {
    if (name == null || !availableIcons.containsKey(name)) {
      return const Icon(Icons.label_important_outline);
    }
    return Icon(availableIcons[name]);
  }
}

@immutable
class CommandPosition {
  final String id;
  final String label;
  final IconData icon;
  final List<String> mandatoryCommands;


  const CommandPosition({
    required this.id,
    required this.label,
    required this.icon,
    this.mandatoryCommands = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandPosition &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class AppCommandPositions {
  static const appBar = CommandPosition(
    id: 'app_bar',
    label: 'App Bar',
    icon: Icons.web_asset_outlined,
  );
  static const pluginToolbar = CommandPosition(
    id: 'plugin_toolbar',
    label: 'Plugin Toolbar',
    icon: Icons.build_circle_outlined,
  );
  static const contextMenu = CommandPosition(
    id: 'context_menu',
    label: 'Context Menu',
    icon: Icons.touch_app_outlined,
  );
  static const hidden = CommandPosition(
    id: 'hidden',
    label: 'Hidden',
    icon: Icons.visibility_off_outlined,
  );

  static List<CommandPosition> get all => [appBar, pluginToolbar];
}

abstract class Command {
  final String id;
  final String label;
  final Widget icon;
    final List<CommandPosition> defaultPositions;
  final String sourcePlugin;

  const Command({
    required this.id,
    required this.label,
    required this.icon,
    required this.defaultPositions,
    required this.sourcePlugin,
  });

  Future<void> execute(WidgetRef ref);
  bool canExecute(WidgetRef ref);
}

class BaseCommand extends Command {
  final Future<void> Function(WidgetRef) _execute;
  final bool Function(WidgetRef) _canExecute;

  const BaseCommand({
    required super.id,
    required super.label,
    required super.icon,
    required super.defaultPositions,
    required super.sourcePlugin,
    required Future<void> Function(WidgetRef) execute,
    bool Function(WidgetRef)? canExecute,
  }) : _execute = execute,
       _canExecute = canExecute ?? _defaultCanExecute;

  static bool _defaultCanExecute(WidgetRef ref) => true;

  @override
  Future<void> execute(WidgetRef ref) => _execute(ref);

  @override
  bool canExecute(WidgetRef ref) => _canExecute(ref);
}

@immutable
class CommandGroup {
  final String id;
  final String label;
  final String iconName;
  final Widget? icon;
  final List<String> commandIds;
  final bool showLabels;
  final String sourcePlugin;
  final bool isDeletable;
  final List<CommandPosition> defaultPositions; // <-- ADD THIS

  const CommandGroup({
    required this.id,
    required this.label,
    this.iconName = 'folder',
    this.icon,
    this.commandIds = const [],
    this.showLabels = true,
    this.sourcePlugin = 'User',
    this.isDeletable = true,
    this.defaultPositions = const [], // <-- ADD THIS
  });

  Widget get finalIcon => icon ?? CommandIcon.getIcon(iconName);

  CommandGroup copyWith({
    String? label,
    String? iconName,
    Widget? icon,
    List<String>? commandIds,
    bool? showLabels,
    String? sourcePlugin,
    bool? isDeletable,
    List<CommandPosition>? defaultPositions, // <-- ADD THIS
  }) {
    return CommandGroup(
      id: id,
      label: label ?? this.label,
      iconName: iconName ?? this.iconName,
      icon: icon ?? this.icon,
      commandIds: commandIds ?? this.commandIds,
      showLabels: showLabels ?? this.showLabels,
      sourcePlugin: sourcePlugin ?? this.sourcePlugin,
      isDeletable: isDeletable ?? this.isDeletable,
      defaultPositions: defaultPositions ?? this.defaultPositions, // <-- ADD THIS
    );
  }

  // Serialization and Deserialization remain unchanged as defaultPositions
  // are defined at runtime by plugins, not stored in user preferences.
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'iconName': iconName,
    'commandIds': commandIds,
    'showLabels': showLabels,
  };

  factory CommandGroup.fromJson(Map<String, dynamic> json) => CommandGroup(
    id: json['id'],
    label: json['label'],
    iconName: json['iconName'] ?? 'folder',
    commandIds: List<String>.from(json['commandIds']),
    showLabels: json['showLabels'] ?? true,
    sourcePlugin: 'User',
    isDeletable: true,
  );
}

abstract class FileContextCommand {
  final String id;
  final String label;
  final Widget icon;
  final String sourcePlugin;

  const FileContextCommand({
    required this.id,
    required this.label,
    required this.icon,
    required this.sourcePlugin,
  });

  bool canExecuteFor(WidgetRef ref, ProjectDocumentFile item);
  Future<void> executeFor(WidgetRef ref, ProjectDocumentFile item);
}

class BaseFileContextCommand extends FileContextCommand {
  final bool Function(WidgetRef, ProjectDocumentFile) _canExecuteFor;
  final Future<void> Function(WidgetRef, ProjectDocumentFile) _executeFor;

  const BaseFileContextCommand({
    required super.id,
    required super.label,
    required super.icon,
    required super.sourcePlugin,
    required bool Function(WidgetRef, ProjectDocumentFile) canExecuteFor,
    required Future<void> Function(WidgetRef, ProjectDocumentFile) executeFor,
  }) : _canExecuteFor = canExecuteFor,
       _executeFor = executeFor;

  @override
  bool canExecuteFor(WidgetRef ref, ProjectDocumentFile item) =>
      _canExecuteFor(ref, item);

  @override
  Future<void> executeFor(WidgetRef ref, ProjectDocumentFile item) =>
      _executeFor(ref, item);
}

abstract class TabContextCommand {
  final String id;
  final String label;
  final Widget icon;
  final String sourcePlugin;

  const TabContextCommand({
    required this.id,
    required this.label,
    required this.icon,
    required this.sourcePlugin,
  });

  bool canExecuteFor(WidgetRef ref, EditorTab activeTab, EditorTab targetTab);
  Future<void> executeFor(
    WidgetRef ref,
    EditorTab activeTab,
    EditorTab targetTab,
  );
}

class BaseTabContextCommand extends TabContextCommand {
  final bool Function(WidgetRef, EditorTab, EditorTab) _canExecuteFor;
  final Future<void> Function(WidgetRef, EditorTab, EditorTab) _executeFor;

  const BaseTabContextCommand({
    required super.id,
    required super.label,
    required super.icon,
    required super.sourcePlugin,
    required bool Function(WidgetRef, EditorTab, EditorTab) canExecuteFor,
    required Future<void> Function(WidgetRef, EditorTab, EditorTab) executeFor,
  }) : _canExecuteFor = canExecuteFor,
       _executeFor = executeFor;

  @override
  bool canExecuteFor(WidgetRef ref, EditorTab activeTab, EditorTab targetTab) =>
      _canExecuteFor(ref, activeTab, targetTab);

  @override
  Future<void> executeFor(
    WidgetRef ref,
    EditorTab activeTab,
    EditorTab targetTab,
  ) => _executeFor(ref, activeTab, targetTab);
}

class CommandState {
  final Map<String, List<String>> orderedCommandsByPosition;

  final List<String> hiddenOrder;
  final Map<String, Set<String>> commandSources;
  final Map<String, CommandGroup> commandGroups;

  final List<CommandPosition> availablePositions;

  const CommandState({
    this.orderedCommandsByPosition = const {},
    this.hiddenOrder = const [],
    this.commandSources = const {},
    this.commandGroups = const {},
    this.availablePositions = const [],
  });

  CommandState copyWith({
    Map<String, List<String>>? orderedCommandsByPosition,
    List<String>? hiddenOrder,
    Map<String, Set<String>>? commandSources,
    Map<String, CommandGroup>? commandGroups,
    List<CommandPosition>? availablePositions,
  }) {
    return CommandState(
      orderedCommandsByPosition:
          orderedCommandsByPosition ?? this.orderedCommandsByPosition,
      hiddenOrder: hiddenOrder ?? this.hiddenOrder,
      commandSources: commandSources ?? this.commandSources,
      commandGroups: commandGroups ?? this.commandGroups,
      availablePositions: availablePositions ?? this.availablePositions,
    );
  }
}
