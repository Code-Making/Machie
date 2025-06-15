// lib/command/command_notifier.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
  final List<Command> _allRegisteredCommands = [];

  List<Command> get allRegisteredCommands => _allRegisteredCommands;

  Command? getCommand(String id, String sourcePlugin) {
    // First, try to find the specific command for the plugin
    var command = _allRegisteredCommands.firstWhere(
        (c) => c.id == id && c.sourcePlugin == sourcePlugin,
        orElse: () => null!);
    // If not found, find any command with that ID (fallback for core/general commands)
    command ??=
        _allRegisteredCommands.firstWhere((c) => c.id == id, orElse: () => null!);
    return command;
  }

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

    state = state.copyWith(commandSources: commandSources);
    await _loadFromPrefs();
  }

  // --- Group CRUD ---

  void createGroup({required String name, required String iconName}) {
    final newGroup = CommandGroup(
      id: 'group_${const Uuid().v4()}',
      label: name,
      iconName: iconName,
    );

    final newGroups = {...state.commandGroups, newGroup.id: newGroup};
    // Add new group to the toolbar by default
    final newToolbarOrder = [...state.pluginToolbarOrder, newGroup.id];

    state = state.copyWith(
      commandGroups: newGroups,
      pluginToolbarOrder: newToolbarOrder,
    );
    _saveToPrefs();
  }

  void updateGroup(String groupId, {String? newName, String? newIconName}) {
    final oldGroup = state.commandGroups[groupId];
    if (oldGroup == null) return;

    final newGroup = oldGroup.copyWith(
      label: newName,
      iconName: newIconName,
    );
    final newGroups = {...state.commandGroups, groupId: newGroup};
    state = state.copyWith(commandGroups: newGroups);
    _saveToPrefs();
  }

  void deleteGroup(String groupId) {
    final group = state.commandGroups[groupId];
    if (group == null) return;

    final newGroups = Map.from(state.commandGroups)..remove(groupId);
    // Move commands from the deleted group back to the hidden list
    final newHiddenOrder = [...state.hiddenOrder, ...group.commandIds];

    state = state.copyWith(
      commandGroups: newGroups,
      hiddenOrder: newHiddenOrder,
      appBarOrder: state.appBarOrder.where((id) => id != groupId).toList(),
      pluginToolbarOrder:
          state.pluginToolbarOrder.where((id) => id != groupId).toList(),
    );
    _saveToPrefs();
  }

  // --- Command Positioning ---

  void updateCommandPosition(String commandId, CommandPosition newPosition,
      {String? targetGroupId}) {
    // Create mutable copies of state lists
    final newAppBar = List.from(state.appBarOrder);
    final newPluginToolbar = List.from(state.pluginToolbarOrder);
    final newHidden = List.from(state.hiddenOrder);
    final newGroups = Map.of(state.commandGroups);

    // Remove command from all possible old locations
    newAppBar.remove(commandId);
    newPluginToolbar.remove(commandId);
    newHidden.remove(commandId);
    newGroups.forEach((key, group) {
      final newCommandIds = List<String>.from(group.commandIds)..remove(commandId);
      newGroups[key] = group.copyWith(commandIds: newCommandIds);
    });

    // Add command to its new location
    if (targetGroupId != null) {
      final group = newGroups[targetGroupId];
      if (group != null) {
        final newGroupCommands = [...group.commandIds, commandId];
        newGroups[targetGroupId] = group.copyWith(commandIds: newGroupCommands);
      }
    } else {
      switch (newPosition) {
        case CommandPosition.appBar:
          newAppBar.add(commandId);
          break;
        case CommandPosition.pluginToolbar:
          newPluginToolbar.add(commandId);
          break;
        case CommandPosition.hidden:
        default:
          newHidden.add(commandId);
          break;
      }
    }

    state = state.copyWith(
      appBarOrder: newAppBar,
      pluginToolbarOrder: newPluginToolbar,
      hiddenOrder: newHidden,
      commandGroups: newGroups,
    );
    _saveToPrefs();
  }

  // --- Persistence ---

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('command_app_bar', state.appBarOrder);
    await prefs.setStringList('command_plugin_toolbar', state.pluginToolbarOrder);
    await prefs.setStringList('command_hidden', state.hiddenOrder);
    final encodedGroups = state.commandGroups.map(
      (key, value) => MapEntry(key, jsonEncode(value.toJson())),
    );
    await prefs.setString('command_groups', jsonEncode(encodedGroups));
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Groups
    final Map<String, CommandGroup> loadedGroups = {};
    final groupsJsonString = prefs.getString('command_groups');
    if (groupsJsonString != null) {
      // CORRECTED: Explicitly cast the decoded JSON maps
      final Map<String, dynamic> decoded = jsonDecode(groupsJsonString);
      decoded.forEach((key, value) {
        loadedGroups[key] = CommandGroup.fromJson(jsonDecode(value as String) as Map<String,dynamic>);
      });
    }

    // Load Order Lists
    // CORRECTED: Explicit casting for lists
    final appBar = prefs.getStringList('command_app_bar') ?? [];
    final pluginToolbar = prefs.getStringList('command_plugin_toolbar') ?? [];
    
    // Now we can calculate the hidden commands based on the ones that have been placed.
    final hidden = prefs.getStringList('command_hidden') ?? _getOrphanedCommands(
        appBar: appBar, pluginToolbar: pluginToolbar, groups: loadedGroups);

    state = state.copyWith(
      appBarOrder: appBar,
      pluginToolbarOrder: pluginToolbar,
      hiddenOrder: hidden,
      commandGroups: loadedGroups,
    );
  }

  List<String> _getOrphanedCommands({
      required List<String> appBar,
      required List<String> pluginToolbar,
      required Map<String, CommandGroup> groups}) {
    final placedCommands = {
      ...appBar,
      ...pluginToolbar,
      ...groups.values.expand((g) => g.commandIds)
    };
    return _allRegisteredCommands
        .map((c) => c.id)
        .where((id) => !placedCommands.contains(id))
        .toSet() // Use a Set to remove duplicates from different plugins
        .toList();
  }
}