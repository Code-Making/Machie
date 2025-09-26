// lib/command/command_notifier.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import '../editor/plugins/plugin_registry.dart';
import '../app/app_commands.dart'; // REFACTOR: Import app-level commands
import 'command_models.dart';

export 'command_models.dart';

final commandProvider = StateNotifierProvider<CommandNotifier, CommandState>((
  ref,
) {
  // REFACTOR: Watch active plugins to re-initialize if they change
  final plugins = ref.watch(activePluginsProvider);
  return CommandNotifier(ref: ref, plugins: plugins);
});

class CommandNotifier extends StateNotifier<CommandState> {
  final Ref ref;
  final List<Command> _allRegisteredCommands = [];

  List<Command> get allRegisteredCommands => _allRegisteredCommands;

  Command? getCommand(String id, String sourcePlugin) {
    for (final command in _allRegisteredCommands) {
      if (command.id == id && command.sourcePlugin == sourcePlugin) {
        return command;
      }
    }
    for (final command in _allRegisteredCommands) {
      if (command.id == id) {
        return command;
      }
    }
    return null;
  }

  CommandNotifier({required this.ref, required Set<EditorPlugin> plugins})
    : super(const CommandState()) {
    _initializeCommands(plugins);
  }

  void _initializeCommands(Set<EditorPlugin> plugins) async {
    _allRegisteredCommands.clear();
    final commandSources = <String, Set<String>>{};

    // REFACTORED: Add app-level commands from plugins.
    final allAppCommands = AppCommands.getCommands();
    final allPluginEditorCommands = plugins.expand((p) => p.getCommands());
    final allPluginAppCommands = plugins.expand(
      (p) => p.getAppCommands(),
    ); // <-- NEW

    // Combine them all.
    final combinedCommands = [
      ...allAppCommands,
      ...allPluginEditorCommands,
      ...allPluginAppCommands, // <-- NEW
    ];

    for (final cmd in combinedCommands) {
      _allRegisteredCommands.add(cmd);
      (commandSources[cmd.id] ??= {}).add(cmd.sourcePlugin);
    }

    state = state.copyWith(commandSources: commandSources);
    await _loadFromPrefs();
  }

  // --- Group CRUD (unchanged) ---
  void createGroup({required String name, required String iconName}) {
    final newGroup = CommandGroup(
      id: 'group_${const Uuid().v4()}',
      label: name,
      iconName: iconName,
    );
    final newGroups = {...state.commandGroups, newGroup.id: newGroup};
    state = state.copyWith(commandGroups: newGroups);
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

  // --- Command Positioning (unchanged) ---
  Map<String, List<String>> _getMutableLists() {
    return {
      'appBar': List<String>.from(state.appBarOrder),
      'pluginToolbar': List<String>.from(state.pluginToolbarOrder),
      'hidden': List<String>.from(state.hiddenOrder),
      ...state.commandGroups.map(
        (id, group) => MapEntry(id, List<String>.from(group.commandIds)),
      ),
    };
  }

  void _updateStateWithLists(Map<String, List<String>> lists) {
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

  void reorderItemInList({
    required String listId,
    required int oldIndex,
    required int newIndex,
  }) {
    final lists = _getMutableLists();
    final list = lists[listId];
    if (list == null) return;

    if (oldIndex < newIndex) newIndex--;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    _updateStateWithLists(lists);
  }

  void removeItemFromList({
    required String itemId,
    required String fromListId,
  }) {
    final lists = _getMutableLists();
    lists[fromListId]?.remove(itemId);
    if (!state.commandGroups.containsKey(itemId)) {
      final isPlacedElsewhere =
          (lists['appBar']?.contains(itemId) ?? false) ||
          (lists['pluginToolbar']?.contains(itemId) ?? false) ||
          state.commandGroups.values.any((g) => g.commandIds.contains(itemId));
      if (!isPlacedElsewhere) {
        lists['hidden']?.add(itemId);
      }
    }
    _updateStateWithLists(lists);
  }

  void addItemToList({required String itemId, required String toListId}) {
    final lists = _getMutableLists();
    final targetList = lists[toListId];
    if (targetList == null) return;

    if (!targetList.contains(itemId)) {
      targetList.add(itemId);
    }
    _updateStateWithLists(lists);
  }

  // --- Persistence ---
  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('command_app_bar', state.appBarOrder);
    await prefs.setStringList(
      'command_plugin_toolbar',
      state.pluginToolbarOrder,
    );
    await prefs.setStringList('command_hidden', state.hiddenOrder);
    final encodedGroups = state.commandGroups.map(
      (key, value) => MapEntry(key, jsonEncode(value.toJson())),
    );
    await prefs.setString('command_groups', jsonEncode(encodedGroups));
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final allKnownCommandIds = _allRegisteredCommands.map((c) => c.id).toSet();
    final Map<String, CommandGroup> loadedGroups = {};
    final groupsJsonString = prefs.getString('command_groups');

    if (groupsJsonString != null) {
      final Map<String, dynamic> decoded = jsonDecode(groupsJsonString);
      decoded.forEach((key, value) {
        final group = CommandGroup.fromJson(
          jsonDecode(value as String) as Map<String, dynamic>,
        );
        final cleanCommandIds =
            group.commandIds.where(allKnownCommandIds.contains).toList();
        loadedGroups[key] = group.copyWith(commandIds: cleanCommandIds);
      });
    }

    final allValidGroupIds = loadedGroups.keys.toSet();
    final allValidItemIds = {...allKnownCommandIds, ...allValidGroupIds};

    final loadedAppBar = prefs.getStringList('command_app_bar') ?? [];
    final loadedToolbar = prefs.getStringList('command_plugin_toolbar') ?? [];
    final loadedHidden = prefs.getStringList('command_hidden') ?? [];

    final cleanAppBar = loadedAppBar.where(allValidItemIds.contains).toList();
    final cleanToolbar = loadedToolbar.where(allValidItemIds.contains).toList();
    final cleanHidden =
        loadedHidden.where(allKnownCommandIds.contains).toList();

    final allPlacedCommandIds = {
      ...cleanAppBar.where((id) => !loadedGroups.containsKey(id)),
      ...cleanToolbar.where((id) => !loadedGroups.containsKey(id)),
      ...cleanHidden,
      ...loadedGroups.values.expand((g) => g.commandIds),
    };

    // REFACTOR: Place new commands in their default positions instead of hiding them.
    final orphanedCommandIds = allKnownCommandIds.where(
      (id) => !allPlacedCommandIds.contains(id),
    );

    for (final commandId in orphanedCommandIds) {
      final command = _allRegisteredCommands.firstWhereOrNull(
        (c) => c.id == commandId,
      );
      if (command != null) {
        switch (command.defaultPosition) {
          case CommandPosition.appBar:
            cleanAppBar.add(commandId);
            break;
          case CommandPosition.pluginToolbar:
            cleanToolbar.add(commandId);
            break;
          default:
            cleanHidden.add(commandId);
            break;
        }
      }
    }

    state = state.copyWith(
      appBarOrder: cleanAppBar,
      pluginToolbarOrder: cleanToolbar,
      hiddenOrder: cleanHidden,
      commandGroups: loadedGroups,
    );
  }
}
