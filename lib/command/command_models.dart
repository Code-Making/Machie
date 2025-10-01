// =========================================
// UPDATED: lib/command/command_models.dart
// =========================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/file_handler/file_handler.dart';

// --- Icon Management (Unchanged) ---
class CommandIcon {
  // ... (content is unchanged)
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

// =======================================================================
// REFACTORED: CommandPosition is now a flexible class instead of an enum.
// =======================================================================
@immutable
class CommandPosition {
  final String id;
  final String label;
  final IconData icon;

  const CommandPosition({
    required this.id,
    required this.label,
    required this.icon,
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

/// Defines the built-in command positions provided by the application shell.
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
  
  /// A list of all default positions, useful for registration.
  static List<CommandPosition> get all => [appBar, pluginToolbar];
}
// =======================================================================

abstract class Command {
  final String id;
  final String label;
  final Widget icon;
  // REFACTORED: Now uses the new CommandPosition class.
  final CommandPosition defaultPosition;
  final String sourcePlugin;

  const Command({
    required this.id,
    required this.label,
    required this.icon,
    required this.defaultPosition,
    required this.sourcePlugin,
  });

  Future<void> execute(WidgetRef ref);
  bool canExecute(WidgetRef ref);
}

class BaseCommand extends Command {
  // ... (content is unchanged)
  final Future<void> Function(WidgetRef) _execute;
  final bool Function(WidgetRef) _canExecute;

  const BaseCommand({
    required super.id,
    required super.label,
    required super.icon,
    required super.defaultPosition,
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
  // ... (content is unchanged)
  final String id;
  final String label;
  final String iconName;
  final List<String> commandIds;

  const CommandGroup({
    required this.id,
    required this.label,
    required this.iconName,
    this.commandIds = const [],
  });

  Widget get icon => CommandIcon.getIcon(iconName);

  CommandGroup copyWith({
    String? label,
    String? iconName,
    List<String>? commandIds,
  }) {
    return CommandGroup(
      id: id,
      label: label ?? this.label,
      iconName: iconName ?? this.iconName,
      commandIds: commandIds ?? this.commandIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'iconName': iconName,
    'commandIds': commandIds,
  };

  factory CommandGroup.fromJson(Map<String, dynamic> json) => CommandGroup(
    id: json['id'],
    label: json['label'],
    iconName: json['iconName'],
    commandIds: List<String>.from(json['commandIds']),
  );
}

abstract class FileContextCommand {
  // ... (content is unchanged)
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

  bool canExecuteFor(WidgetRef ref, DocumentFile item);
  Future<void> executeFor(WidgetRef ref, DocumentFile item);
}

class BaseFileContextCommand extends FileContextCommand {
  // ... (content is unchanged)
  final bool Function(WidgetRef, DocumentFile) _canExecuteFor;
  final Future<void> Function(WidgetRef, DocumentFile) _executeFor;

  const BaseFileContextCommand({
    required super.id,
    required super.label,
    required super.icon,
    required super.sourcePlugin,
    required bool Function(WidgetRef, DocumentFile) canExecuteFor,
    required Future<void> Function(WidgetRef, DocumentFile) executeFor,
  }) : _canExecuteFor = canExecuteFor,
       _executeFor = executeFor;

  @override
  bool canExecuteFor(WidgetRef ref, DocumentFile item) =>
      _canExecuteFor(ref, item);

  @override
  Future<void> executeFor(WidgetRef ref, DocumentFile item) =>
      _executeFor(ref, item);
}

// REFACTORED: The main state object is now much more generic.
class CommandState {
  // Holds the order of command/group IDs for each position.
  // Key: CommandPosition.id, Value: List of command/group IDs.
  final Map<String, List<String>> orderedCommandsByPosition;

  final List<String> hiddenOrder;
  final Map<String, Set<String>> commandSources;
  final Map<String, CommandGroup> commandGroups;
  
  // A list of all available positions, discovered at runtime.
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
      orderedCommandsByPosition: orderedCommandsByPosition ?? this.orderedCommandsByPosition,
      hiddenOrder: hiddenOrder ?? this.hiddenOrder,
      commandSources: commandSources ?? this.commandSources,
      commandGroups: commandGroups ?? this.commandGroups,
      availablePositions: availablePositions ?? this.availablePositions,
    );
  }
}