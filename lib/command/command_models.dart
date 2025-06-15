// lib/command/command_models.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/file_handler/file_handler.dart';

// --------------------
//   Command System
// --------------------

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
  })  : _execute = execute,
        _canExecute = canExecute ?? _defaultCanExecute;

  static bool _defaultCanExecute(WidgetRef ref) => true;

  @override
  Future<void> execute(WidgetRef ref) => _execute(ref);

  @override
  bool canExecute(WidgetRef ref) => _canExecute(ref);
}

// NEW: Command Group Model
@immutable
class CommandGroup {
  final String id;
  final String label;
  final Widget icon;
  final List<String> commandIds;

  const CommandGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.commandIds,
  });
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
  })  : _canExecuteFor = canExecuteFor,
        _executeFor = executeFor;

  @override
  bool canExecuteFor(WidgetRef ref, DocumentFile item) =>
      _canExecuteFor(ref, item);

  @override
  Future<void> executeFor(WidgetRef ref, DocumentFile item) =>
      _executeFor(ref, item);
}

enum CommandPosition {
  appBar,
  pluginToolbar,
  both,
  hidden,
  contextMenu,
}

class CommandState {
  final List<String> appBarOrder;
  final List<String> pluginToolbarOrder;
  final List<String> hiddenOrder;
  final Map<String, Set<String>> commandSources;
  final Map<String, CommandGroup> commandGroups; // NEW

  const CommandState({
    this.appBarOrder = const [],
    this.pluginToolbarOrder = const [],
    this.hiddenOrder = const [],
    this.commandSources = const {},
    this.commandGroups = const {}, // NEW
  });

  CommandState copyWith({
    List<String>? appBarOrder,
    List<String>? pluginToolbarOrder,
    List<String>? hiddenOrder,
    Map<String, Set<String>>? commandSources,
    Map<String, CommandGroup>? commandGroups, // NEW
  }) {
    return CommandState(
      appBarOrder: appBarOrder ?? this.appBarOrder,
      pluginToolbarOrder: pluginToolbarOrder ?? this.pluginToolbarOrder,
      hiddenOrder: hiddenOrder ?? this.hiddenOrder,
      commandSources: commandSources ?? this.commandSources,
      commandGroups: commandGroups ?? this.commandGroups, // NEW
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
        return [];
      case CommandPosition.both:
        return [];
    }
  }
}