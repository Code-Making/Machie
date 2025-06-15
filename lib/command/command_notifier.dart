// lib/command/command_notifier.dart
import 'dart:async';

import 'package:flutter/material.dart'; // NEW IMPORT
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../plugins/plugin_models.dart';
import '../plugins/plugin_registry.dart';

import 'command_models.dart';

final commandProvider = StateNotifierProvider<CommandNotifier, CommandState>((
  ref,
) {
  return CommandNotifier(ref: ref, plugins: ref.watch(activePluginsProvider));
});

class CommandNotifier extends StateNotifier<CommandState> {
  final Ref ref;
  // MODIFIED: This is now a flat list of ALL registered commands.
  final List<Command> _allRegisteredCommands = [];

  // Public getter for providers to access all commands
  List<Command> get allRegisteredCommands => _allRegisteredCommands;

  Command? getCommand(String id, String sourcePlugin) =>
      _allRegisteredCommands.firstWhere(
          (c) => c.id == id && c.sourcePlugin == sourcePlugin);

  CommandNotifier({required this.ref, required Set<EditorPlugin> plugins})
      : super(const CommandState()) {
    _initializeCommands(plugins);
  }

  void _initializeCommands(Set<EditorPlugin> plugins) async {
    _allRegisteredCommands.clear();

    final commandSources = <String, Set<String>>{};
    final allPluginCommands = plugins.expand((p) => p.getCommands());

    for (final cmd in allPluginCommands) {
      _allRegisteredCommands.add(cmd);
      (commandSources[cmd.id] ??= {}).add(cmd.sourcePlugin);
    }

    // --- DEMO: Define a command group ---
    const editingGroupId = 'editing_group';
    final commandGroups = {
      editingGroupId: const CommandGroup(
        id: editingGroupId,
        label: 'Editing',
        icon: Icon(Icons.edit_note),
        commandIds: [
          'indent',
          'outdent',
          'toggle_comment',
          'reformat'
        ],
      )
    };

    // --- End Demo ---

    state = CommandState(
      commandSources: commandSources,
      commandGroups: commandGroups,
    );
    await _loadFromPrefs();
  }

  void updateOrder(CommandPosition position, List<String> newOrder) {
    // ... (updateOrder and updateCommandPosition logic is complex with groups,
    //      leaving as-is for now but would need updating for a full settings UI)
  }

  void updateCommandPosition(String commandId, CommandPosition newPosition) {
    // ...
  }

  Future<void> _saveToPrefs() async {
    // ... (saving logic would also need to account for groups)
  }

  Future<void> _loadFromPrefs() async {
    // For demonstration, we will use hardcoded defaults.
    // A real implementation would merge saved prefs with plugin defaults.

    // Get all unique command and group IDs from plugins
    final allCommandIds = _allRegisteredCommands.map((c) => c.id).toSet();
    final allGroupIds = state.commandGroups.keys.toSet();

    // Default AppBar: save command
    final appBar = ['save'];

    // Default Toolbar: a mix of individual commands and the new group
    final pluginToolbar = [
      'copy',
      'cut',
      'paste',
      'editing_group', // The ID of our new group
      'undo',
      'redo'
    ];

    state = state.copyWith(
      appBarOrder: appBar.where((id) => allCommandIds.contains(id) || allGroupIds.contains(id)).toList(),
      pluginToolbarOrder: pluginToolbar.where((id) => allCommandIds.contains(id) || allGroupIds.contains(id)).toList(),
    );
  }
}