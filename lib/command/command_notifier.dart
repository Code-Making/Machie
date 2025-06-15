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
    var command = _allRegisteredCommands.firstWhere(
        (c) => c.id == id && c.sourcePlugin == sourcePlugin,
        orElse: () => null!);
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
    final newGroup = oldGroup.copyWith(label: newName, iconName: newIconName);
    final newGroups = {...state.commandGroups, groupId: newGroup};
    state = state.copyWith(commandGroups: newGroups);
    _saveToPrefs();
  }

  void deleteGroup(String groupId) {
    final group = state.commandGroups[groupId];
    if (group == null) return;
    final newGroups = Map.of(state.commandGroups)..remove(groupId);
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

  // NEW: A single, powerful method to move commands and groups between any list.
  void moveItem(
      {required String itemId,
      required String fromListId,
      required String toListId,
      required int newIndex}) {
    // Get mutable copies of all lists
    final lists = {
      'appBar': List<String>.from(state.appBarOrder),
      'pluginToolbar': List<String>.from(state.pluginToolbarOrder),
      'hidden': List<String>.from(state.hiddenOrder),
      ...state.commandGroups
          .map((id, group) => MapEntry(id, List<String>.from(group.commandIds)))
    };

    // Remove from the old list
    lists[fromListId]?.remove(itemId);
    
    // Add to the new list at the correct index
    final targetList = lists[toListId];
    if (targetList == null) return;
    if (newIndex < 0 || newIndex > targetList.length) {
      targetList.add(itemId);
    } else {
      targetList.insert(newIndex, itemId);
    }

    // Create the final state maps/lists
    final newGroups = Map.of(state.commandGroups);
    lists.forEach((listId, commands) {
      if (newGroups.containsKey(listId)) {
        newGroups[listId] = newGroups[listId]!.copyWith(commandIds: commands);
      }
    });

    state = state.copyWith(
      appBarOrder: lists['appBar'],
      pluginToolbarOrder: lists['pluginToolbar'],
      hiddenOrder: lists['hidden'],
      commandGroups: newGroups,
    );
    _saveToPrefs();
  }

  // --- Persistence ---

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('command_app_bar', state.appBarOrder);
    await prefs.setStringList(
        'command_plugin_toolbar', state.pluginToolbarOrder);
    await prefs.setStringList('command_hidden', state.hiddenOrder);
    final encodedGroups = state.commandGroups
        .map((key, value) => MapEntry(key, jsonEncode(value.toJson())));
    await prefs.setString('command_groups', jsonEncode(encodedGroups));
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final Map<String, CommandGroup> loadedGroups = {};
    final groupsJsonString = prefs.getString('command_groups');
    if (groupsJsonString != null) {
      final Map<String, dynamic> decoded = jsonDecode(groupsJsonString);
      decoded.forEach((key, value) {
        loadedGroups[key] =
            CommandGroup.fromJson(jsonDecode(value as String) as Map<String, dynamic>);
      });
    }

    final appBar = prefs.getStringList('command_app_bar') ?? [];
    final pluginToolbar = prefs.getStringList('command_plugin_toolbar') ?? [];
    
    // CORRECTED: Load hidden list and then add any new/orphaned commands to it.
    final loadedHidden = prefs.getStringList('command_hidden') ?? [];
    final orphaned = _getOrphanedCommands(
        appBar: appBar, pluginToolbar: pluginToolbar, groups: loadedGroups);

    // Combine loaded hidden commands with any new ones, avoiding duplicates.
    final finalHidden = {...loadedHidden, ...orphaned}.toList();

    state = state.copyWith(
      appBarOrder: appBar,
      pluginToolbarOrder: pluginToolbar,
      hiddenOrder: finalHidden,
      commandGroups: loadedGroups,
    );
  }

  List<String> _getOrphanedCommands(
      {required List<String> appBar,
      required List<String> pluginToolbar,
      required Map<String, CommandGroup> groups}) {
    final placedItemIds = {
      ...appBar,
      ...pluginToolbar,
      ...groups.keys,
      ...groups.values.expand((g) => g.commandIds)
    };
    final allCommandIds = _allRegisteredCommands.map((c) => c.id).toSet();
    return allCommandIds.where((id) => !placedItemIds.contains(id)).toList();
  }
}