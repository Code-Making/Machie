// lib/command/command_models.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/file_handler/file_handler.dart';

// --- Icon Management ---

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

// --- Command System ---

abstract class Command {
  final String id;
  final String label;
  final Widget icon;
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

// MODIFIED: CommandGroup now stores the icon name for persistence.
@immutable
class CommandGroup {
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

  // Transient getter for the UI
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

enum CommandPosition { appBar, pluginToolbar, both, hidden, contextMenu }

class CommandState {
  final List<String> appBarOrder;
  final List<String> pluginToolbarOrder;
  final List<String> hiddenOrder;
  final Map<String, Set<String>> commandSources;
  final Map<String, CommandGroup> commandGroups;

  const CommandState({
    this.appBarOrder = const [],
    this.pluginToolbarOrder = const [],
    this.hiddenOrder = const [],
    this.commandSources = const {},
    this.commandGroups = const {},
  });

  CommandState copyWith({
    List<String>? appBarOrder,
    List<String>? pluginToolbarOrder,
    List<String>? hiddenOrder,
    Map<String, Set<String>>? commandSources,
    Map<String, CommandGroup>? commandGroups,
  }) {
    return CommandState(
      appBarOrder: appBarOrder ?? this.appBarOrder,
      pluginToolbarOrder: pluginToolbarOrder ?? this.pluginToolbarOrder,
      hiddenOrder: hiddenOrder ?? this.hiddenOrder,
      commandSources: commandSources ?? this.commandSources,
      commandGroups: commandGroups ?? this.commandGroups,
    );
  }

  List<String> getOrderForPosition(CommandPosition position) {
    switch (position) {
      case CommandPosition.appBar:
        return appBarOrder;
      case CommandPosition.pluginToolbar:
        return pluginToolbarOrder;
      case CommandPosition.hidden:
        return hiddenOrder;
      case CommandPosition.contextMenu:
      case CommandPosition.both:
        return [];
    }
  }
}
