import 'dart:async';

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
  final List<Command> _coreCommands;
  final Map<String, Command> _allCommands = {};
  final Map<String, Set<String>> _commandSources = {};

  Command? getCommand(String id) => _allCommands[id];

  CommandNotifier({required this.ref, required Set<EditorPlugin> plugins})
    : _coreCommands = _buildCoreCommands(ref),
      super(const CommandState()) {
    _initializeCommands(plugins);
  }

  List<Command> getVisibleCommands(CommandPosition position) {
    final commands = switch (position) {
      CommandPosition.appBar => [
        ...state.appBarOrder,
        ...state.pluginToolbarOrder.where(
          (id) => _allCommands[id]?.defaultPosition == CommandPosition.both,
        ),
      ],
      CommandPosition.pluginToolbar => [
        ...state.pluginToolbarOrder,
        ...state.appBarOrder.where(
          (id) => _allCommands[id]?.defaultPosition == CommandPosition.both,
        ),
      ],
      _ => [],
    };

    return commands.map((id) => _allCommands[id]).whereType<Command>().toList();
  }

  static List<Command> _buildCoreCommands(Ref ref) => [
    /* BaseCommand(
      id: 'save',
      label: 'Save',
      icon: const Icon(Icons.save),
      defaultPosition: CommandPosition.appBar,
      sourcePlugin: 'Core',
      execute: (ref) => ref.read(sessionProvider.notifier).saveSession(),
      canExecute: (ref) => ref.watch(sessionProvider
          .select((s) => s.currentTab?.isDirty ?? false)),
    ),*/
  ];

  void updateOrder(CommandPosition position, List<String> newOrder) {
    switch (position) {
      case CommandPosition.appBar:
        state = state.copyWith(appBarOrder: newOrder);
        break;
      case CommandPosition.pluginToolbar:
        state = state.copyWith(pluginToolbarOrder: newOrder);
        break;
      case CommandPosition.hidden:
        state = state.copyWith(hiddenOrder: newOrder);
        break;
      case CommandPosition.both:
      case CommandPosition.contextMenu:
        // These positions are not ordered via CommandNotifier state
        break;
    }
    _saveToPrefs();
  }

  void _initializeCommands(Set<EditorPlugin> plugins) async {
    final allCommands = [
      ..._coreCommands,
      ...plugins.expand((p) => p.getCommands()),
    ];

    for (final cmd in allCommands) {
      if (_allCommands.containsKey(cmd.id)) {
        _commandSources[cmd.id]!.add(cmd.sourcePlugin);
      } else {
        _allCommands[cmd.id] = cmd;
        _commandSources[cmd.id] = {cmd.sourcePlugin};
      }
    }

    // Initial state setup
    state = CommandState(
      appBarOrder:
          _coreCommands
              .where((c) => c.defaultPosition == CommandPosition.appBar)
              .map((c) => c.id)
              .toList(),
      pluginToolbarOrder:
          _coreCommands
              .where((c) => c.defaultPosition == CommandPosition.pluginToolbar)
              .map((c) => c.id)
              .toList(),
      commandSources: _commandSources,
    );
    await _loadFromPrefs(plugins);
  }

  void updateCommandPosition(String commandId, CommandPosition newPosition) {
    List<String> newAppBar = List.from(state.appBarOrder);
    List<String> newPluginToolbar = List.from(state.pluginToolbarOrder);
    List<String> newHidden = List.from(state.hiddenOrder);

    newAppBar.remove(commandId);
    newPluginToolbar.remove(commandId);
    newHidden.remove(commandId);

    switch (newPosition) {
      case CommandPosition.appBar:
        newAppBar.add(commandId);
        break;
      case CommandPosition.pluginToolbar:
        newPluginToolbar.add(commandId);
        break;
      case CommandPosition.hidden:
        newHidden.add(commandId);
        break;
      case CommandPosition.both:
        newAppBar.add(commandId);
        newPluginToolbar.add(commandId);
        break;
      case CommandPosition.contextMenu:
        // Context menu commands are not globally movable/orderable
        break;
    }

    state = state.copyWith(
      appBarOrder: newAppBar,
      pluginToolbarOrder: newPluginToolbar,
      hiddenOrder: newHidden,
    );
    _saveToPrefs();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('command_app_bar', state.appBarOrder);
    await prefs.setStringList(
      'command_plugin_toolbar',
      state.pluginToolbarOrder,
    );
    await prefs.setStringList('command_hidden', state.hiddenOrder);
  }

  Future<void> _loadFromPrefs(Set<EditorPlugin> plugins) async {
    final prefs = await SharedPreferences.getInstance();
    final appBar = prefs.getStringList('command_app_bar') ?? [];
    final pluginToolbar = prefs.getStringList('command_plugin_toolbar') ?? [];
    final hidden = prefs.getStringList('command_hidden') ?? [];

    final allCommands =
        [
          ..._coreCommands,
          ...ref.read(activePluginsProvider).expand((p) => p.getCommands()),
        ].map((c) => c.id).toSet();

    state = state.copyWith(
      appBarOrder: _mergePosition(
        saved: appBar,
        defaultIds:
            allCommands
                .where(
                  (id) =>
                      _getCommand(id)?.defaultPosition ==
                      CommandPosition.appBar,
                )
                .toList(),
      ),
      pluginToolbarOrder: _mergePosition(
        saved: pluginToolbar,
        defaultIds:
            allCommands
                .where(
                  (id) =>
                      _getCommand(id)?.defaultPosition ==
                      CommandPosition.pluginToolbar,
                )
                .toList(),
      ),
      hiddenOrder: _mergePosition(
        saved: hidden,
        defaultIds:
            allCommands
                .where(
                  (id) =>
                      _getCommand(id)?.defaultPosition ==
                      CommandPosition.hidden,
                )
                .toList(),
      ),
    );
  }

  Command? _getCommand(String id) {
    return _allCommands[id];
  }

  List<String> _mergePosition({
    required List<String> saved,
    required List<String> defaultIds,
  }) {
    // 1. Start with saved commands that still exist
    final validSaved = saved.where((id) => _getCommand(id) != null).toList();

    // 2. Add default commands that weren't saved
    final newDefaults =
        defaultIds.where((id) => !validSaved.contains(id)).toList();

    // 3. Preserve saved order + append new defaults
    return [...validSaved, ...newDefaults];
  }
}
