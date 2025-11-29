import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../app/app_commands.dart';
import '../editor/plugins/editor_plugin_registry.dart';
import 'command_models.dart';

export 'command_models.dart';

final commandProvider = StateNotifierProvider<CommandNotifier, CommandState>((
  ref,
) {
  final plugins = ref.watch(activePluginsProvider);
  return CommandNotifier(ref: ref, plugins: plugins);
});

class CommandNotifier extends StateNotifier<CommandState> {
  final Ref ref;
  final List<Command> _allRegisteredCommands = [];
  final Map<String, CommandGroup> _pluginDefinedGroups =
      {}; // Add this to store plugin groups

  List<Command> get allRegisteredCommands => _allRegisteredCommands;
  Map<String, CommandGroup> get pluginDefinedGroups => _pluginDefinedGroups;

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

  CommandNotifier({required this.ref, required List<EditorPlugin> plugins})
    : super(const CommandState()) {
    _initializeCommands(plugins);
  }

  void _initializeCommands(List<EditorPlugin> plugins) async {
    _allRegisteredCommands.clear();
    _pluginDefinedGroups.clear();

    final commandSources = <String, Set<String>>{};
    final allAppCommands = AppCommands.getCommands();
    final allPluginEditorCommands = plugins.expand((p) => p.getCommands());
    final allPluginAppCommands = plugins.expand((p) => p.getAppCommands());
    for (final plugin in plugins) {
      for (final group in plugin.getCommandGroups()) {
        _pluginDefinedGroups[group.id] = group.copyWith(
          sourcePlugin: plugin.id,
          isDeletable: false,
        );
      }
    }

    final combinedCommands = [
      ...allAppCommands,
      ...allPluginEditorCommands,
      ...allPluginAppCommands,
    ];
    for (final cmd in combinedCommands) {
      _allRegisteredCommands.add(cmd);
      (commandSources[cmd.id] ??= {}).add(cmd.sourcePlugin);
    }

    final allPositions = <CommandPosition>[
      ...AppCommandPositions.all,
      ...plugins.expand((p) => p.getCommandPositions()),
    ];

    state = state.copyWith(
      commandSources: commandSources,
      availablePositions: allPositions,
    );
    await _loadFromPrefs();
  }

  void createGroup({
    required String name,
    required String iconName,
    required bool showLabels,
  }) {
    final newGroup = CommandGroup(
      id: 'group_${const Uuid().v4()}',
      label: name,
      iconName: iconName,
      showLabels: showLabels,
    );
    final newGroups = {...state.commandGroups, newGroup.id: newGroup};
    final newPositions = Map.of(state.orderedCommandsByPosition);
    for (final list in newPositions.values) {
      list.remove(newGroup.id);
    }
    state = state.copyWith(
      commandGroups: newGroups,
      orderedCommandsByPosition: newPositions,
    );
    _saveToPrefs();
  }

  void updateGroup(
    String groupId, {
    String? newName,
    String? newIconName,
    bool? newShowLabels,
  }) {
    final oldGroup = state.commandGroups[groupId];
    if (oldGroup == null) return;
    final newGroup = oldGroup.copyWith(
      label: newName,
      iconName: newIconName,
      showLabels: newShowLabels,
    );
    final newGroups = {...state.commandGroups, groupId: newGroup};
    state = state.copyWith(commandGroups: newGroups);
    _saveToPrefs();
  }

  void deleteGroup(String groupId) {
    final group = state.commandGroups[groupId];
    if (group == null) return;
    final newGroups = Map.of(state.commandGroups)..remove(groupId);
    final newHiddenOrder = [...state.hiddenOrder, ...group.commandIds];

    final newPositions = Map<String, List<String>>.from(
      state.orderedCommandsByPosition,
    );
    newPositions.forEach((key, value) {
      newPositions[key] = value.where((id) => id != groupId).toList();
    });

    state = state.copyWith(
      commandGroups: newGroups,
      hiddenOrder: newHiddenOrder,
      orderedCommandsByPosition: newPositions,
    );
    _saveToPrefs();
  }

  Map<String, List<String>> _getMutableLists() {
    return {
      'hidden': List<String>.from(state.hiddenOrder),
      ...Map.from(
        state.orderedCommandsByPosition,
      ).map((key, value) => MapEntry(key, List<String>.from(value))),
      ...state.commandGroups.map(
        (id, group) => MapEntry(id, List<String>.from(group.commandIds)),
      ),
    };
  }

  void _updateStateWithLists(Map<String, List<String>> lists) {
    final newGroups = Map.of(state.commandGroups);
    final newPositions = Map.of(state.orderedCommandsByPosition);

    lists.forEach((listId, commands) {
      if (newGroups.containsKey(listId)) {
        newGroups[listId] = newGroups[listId]!.copyWith(commandIds: commands);
      } else if (newPositions.containsKey(listId)) {
        newPositions[listId] = commands;
      }
    });

    state = state.copyWith(
      orderedCommandsByPosition: newPositions,
      hiddenOrder: lists['hidden'],
      commandGroups: newGroups,
    );
    _saveToPrefs();
  }

  void reorderItemInList({
    required String positionId,
    required int oldIndex,
    required int newIndex,
  }) {
    final lists = _getMutableLists();
    final list = lists[positionId];
    if (list == null) return;
    if (oldIndex < newIndex) newIndex--;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _updateStateWithLists(lists);
  }

  void removeItemFromList({
    required String itemId,
    required String fromPositionId,
  }) {
    // Check 1: Is this a mandatory item for a CommandPosition? (Unchanged)
    final position = state.availablePositions.firstWhereOrNull(
      (p) => p.id == fromPositionId,
    );
    if (position?.mandatoryCommands.contains(itemId) ?? false) {
      return;
    }

    // --- START: REFINED CHECK FOR PLUGIN GROUPS ---
    // Check 2: Is this a DEFAULT item inside a plugin-defined group?
    final parentGroup = state.commandGroups[fromPositionId];
    if (parentGroup != null && !parentGroup.isDeletable) {
      // The parent is a plugin-defined group.
      // Look up its original definition from when the plugin was loaded.
      final originalPluginGroup = _pluginDefinedGroups[fromPositionId];

      // If the item we're trying to remove was part of that original definition, block the removal.
      if (originalPluginGroup?.commandIds.contains(itemId) ?? false) {
        return; // Silently ignore removal of a default/mandatory command from a plugin group.
      }
      // If we reach here, it means it's a user-added item in a plugin group, so removal is allowed.
    }
    // --- END: REFINED CHECK ---

    // If neither check fails, proceed with removal.
    final lists = _getMutableLists();
    lists[fromPositionId]?.remove(itemId);
    if (!state.commandGroups.containsKey(itemId)) {
      final isPlacedElsewhere = lists.entries
          .where(
            (entry) => entry.key != 'hidden' && entry.key != fromPositionId,
          )
          .any((entry) => entry.value.contains(itemId));
      if (!isPlacedElsewhere) {
        lists['hidden']?.add(itemId);
      }
    }
    _updateStateWithLists(lists);
  }

  void addItemToList({required String itemId, required String toPositionId}) {
    final lists = _getMutableLists();
    final targetList = lists[toPositionId];
    if (targetList == null) return;

    if (!targetList.contains(itemId)) {
      targetList.add(itemId);
    }

    lists['hidden']?.remove(itemId);

    _updateStateWithLists(lists);
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'command_positions',
      jsonEncode(state.orderedCommandsByPosition),
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

    final Map<String, CommandGroup> loadedGroups = Map.from(
      _pluginDefinedGroups,
    );
    final groupsJsonString = prefs.getString('command_groups');
    if (groupsJsonString != null) {
      final Map<String, dynamic> decoded = jsonDecode(groupsJsonString);
      decoded.forEach((key, value) {
        final savedGroupData = CommandGroup.fromJson(
          jsonDecode(value as String) as Map<String, dynamic>,
        );

        // If a plugin group has saved state, merge it. Otherwise, it's a user group.
        if (loadedGroups.containsKey(key)) {
          final pluginGroup = loadedGroups[key]!;
          final cleanCommandIds =
              savedGroupData.commandIds
                  .where(allKnownCommandIds.contains)
                  .toList();
          loadedGroups[key] = pluginGroup.copyWith(
            commandIds: cleanCommandIds,
            showLabels: savedGroupData.showLabels,
          );
        } else {
          // This is a user-created group.
          final cleanCommandIds =
              savedGroupData.commandIds
                  .where(allKnownCommandIds.contains)
                  .toList();
          loadedGroups[key] = savedGroupData.copyWith(
            commandIds: cleanCommandIds,
          );
        }
      });
    }

    final allValidGroupIds = loadedGroups.keys.toSet();
    final allValidItemIds = {...allKnownCommandIds, ...allValidGroupIds};

    final Map<String, List<String>> loadedPositions = {};
    final positionsJsonString = prefs.getString('command_positions');
    if (positionsJsonString != null) {
      final Map<String, dynamic> decoded = jsonDecode(positionsJsonString);
      decoded.forEach((key, value) {
        if (state.availablePositions.any((p) => p.id == key)) {
          loadedPositions[key] =
              (value as List)
                  .cast<String>()
                  .where(allValidItemIds.contains)
                  .toList();
        }
      });
    }

    final loadedHidden = prefs.getStringList('command_hidden') ?? [];
    final cleanHidden =
        loadedHidden.where(allKnownCommandIds.contains).toList();

    final newPositions = {
      for (var pos in state.availablePositions) pos.id: <String>[],
    };
    newPositions.addAll(loadedPositions);

    final allPlacedItemIds = {
      ...newPositions.values.expand(
        (ids) => ids,
      ), // This covers both commands and groups
      ...cleanHidden,
      ...loadedGroups.values.expand((g) => g.commandIds),
    };

    final orphanedCommandIds = allKnownCommandIds.where(
      (id) => !allPlacedItemIds.contains(id),
    );

    final orphanedGroupIds = _pluginDefinedGroups.keys.where(
      (id) => !allPlacedItemIds.contains(id),
    );

    for (final commandId in orphanedCommandIds) {
      final command = _allRegisteredCommands.firstWhereOrNull(
        (c) => c.id == commandId,
      );
      if (command != null) {
        for (final position in command.defaultPositions) {
          final positionId = position.id;
          if (newPositions.containsKey(positionId)) {
            newPositions[positionId]!.add(commandId);
          } else {
            if (!cleanHidden.contains(commandId)) {
              cleanHidden.add(commandId);
            }
          }
        }
      }
    }

    for (final groupId in orphanedGroupIds) {
      final group = _pluginDefinedGroups[groupId];
      if (group != null) {
        if (group.defaultPositions.isNotEmpty) {
          for (final position in group.defaultPositions) {
            final positionId = position.id;
            if (newPositions.containsKey(positionId)) {
              newPositions[positionId]!.add(groupId);
            }
          }
        }
        // If a group has no default position, it will remain "orphaned"
        // and won't appear anywhere. This is reasonable behavior.
      }
    }

    for (final position in state.availablePositions) {
      if (position.mandatoryCommands.isNotEmpty) {
        final positionList = newPositions[position.id]!;
        for (final mandatoryId in position.mandatoryCommands) {
          if (!positionList.contains(mandatoryId)) {
            newPositions.forEach((key, value) {
              value.remove(mandatoryId);
            });

            cleanHidden.remove(mandatoryId);

            positionList.insert(0, mandatoryId);
          }
        }
      }
    }

    state = state.copyWith(
      orderedCommandsByPosition: newPositions,
      hiddenOrder: cleanHidden,
      commandGroups: loadedGroups,
    );
  }
}
