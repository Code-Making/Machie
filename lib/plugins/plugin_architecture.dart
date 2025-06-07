import 'dart:async'; // For FutureOr
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart'; // For CodeLineEditingController, CodeEditorTapRegion

iimport'plugin_registry.dart';
import '../file_system/file_handler.dart'; // For DocumentFile
import '../main.dart'; // For printStream, sessionProvider, canUndoProvider, canRedoProvider, markProvider
import '../session/session_management.dart'; // For SessionState, EditorTab, CodeEditorTab



import 'package:shared_preferences/shared_preferences.dart'; // For SharedPreferences





final commandProvider = StateNotifierProvider<CommandNotifier, CommandState>((ref) {
  return CommandNotifier(ref: ref, plugins: ref.watch(activePluginsProvider));
});

final appBarCommandsProvider = Provider<List<Command>>((ref) {
  final state = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPlugin = ref.watch(sessionProvider.select((s) => s.currentTab?.plugin.runtimeType.toString()));

  return [
    ...state.appBarOrder,
    ...state.pluginToolbarOrder.where(
      (id) => notifier.getCommand(id)?.defaultPosition == CommandPosition.both,
    ),
  ].map((id) => notifier.getCommand(id))
  .where((cmd) => _shouldShowCommand(cmd!, currentPlugin))
  .whereType<Command>()
  .toList();
});

final pluginToolbarCommandsProvider = Provider<List<Command>>((ref) {
  final state = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPlugin = ref.watch(sessionProvider.select((s) => s.currentTab?.plugin.runtimeType.toString()));

  return [
    ...state.pluginToolbarOrder,
    ...state.appBarOrder.where(
      (id) => notifier.getCommand(id)?.defaultPosition == CommandPosition.both,
    ),
  ].map((id) => notifier.getCommand(id))
  .whereType<Command>()
  .where((cmd) => _shouldShowCommand(cmd!, currentPlugin))
  .toList();
});

final bottomToolbarScrollProvider = Provider<ScrollController>((ref) {
  return ScrollController();
});

// Settings Providers (kept here as they are tightly coupled with PluginSettings and AppSettings)
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final plugins = ref.watch(activePluginsProvider);
  return SettingsNotifier(plugins: plugins);
});

// --------------------
//   Editor Plugin
// --------------------

abstract class EditorPlugin {
  // Metadata
  String get name;
  Widget get icon;
  List<Command> getCommands();

  // File type support
  bool supportsFile(DocumentFile file);

  // Tab management
  Future<EditorTab> createTab(DocumentFile file, String content);
  Widget buildEditor(EditorTab tab, WidgetRef ref);

  void activateTab(EditorTab tab, NotifierProviderRef<SessionState> ref);
  void deactivateTab(EditorTab tab, NotifierProviderRef<SessionState> ref);

  PluginSettings? get settings;
  Widget buildSettingsUI(PluginSettings settings);

  Widget buildToolbar(WidgetRef ref) {
    return const SizedBox.shrink(); // Default empty implementation
  }

  // New: Method for deserializing tabs
  Future<EditorTab> createTabFromSerialization(Map<String, dynamic> tabJson, FileHandler fileHandler);

  // Optional lifecycle hooks
  Future<void> dispose() async {}
}


// --------------------
//   Settings Core
// --------------------
abstract class PluginSettings {
  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);
}

class AppSettings {
  final Map<Type, PluginSettings> pluginSettings;

  AppSettings({required this.pluginSettings});

  AppSettings copyWith({Map<Type, PluginSettings>? pluginSettings}) {
    return AppSettings(pluginSettings: pluginSettings ?? this.pluginSettings);
  }
}

// --------------------
//  Settings Providers
// --------------------


class SettingsNotifier extends StateNotifier<AppSettings> {
  final Set<EditorPlugin> _plugins;

  SettingsNotifier({required Set<EditorPlugin> plugins})
    : _plugins = plugins,
      super(AppSettings(pluginSettings: _getDefaultSettings(plugins))) {
    loadSettings();
  }

  static Map<Type, PluginSettings> _getDefaultSettings(
    Set<EditorPlugin> plugins,
  ) {
    return {
      for (final plugin in plugins)
        if (plugin.settings != null)
          plugin.settings.runtimeType: plugin.settings!,
    };
  }

  void updatePluginSettings(PluginSettings newSettings) {
    final updatedSettings = Map<Type, PluginSettings>.from(state.pluginSettings)
      ..[newSettings.runtimeType] = newSettings;

    state = state.copyWith(pluginSettings: updatedSettings);
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsMap = state.pluginSettings.map(
        (type, settings) => MapEntry(type.toString(), settings.toJson()),
      );
      await prefs.setString('app_settings', jsonEncode(settingsMap));
    } catch (e) {
      print('Error saving settings: $e');
    }
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('app_settings');

      if (settingsJson != null) {
        final decoded = jsonDecode(settingsJson) as Map<String, dynamic>;
        final newSettings = Map<Type, PluginSettings>.from(
          state.pluginSettings,
        );

        for (final entry in decoded.entries) {
          try {
            final plugin = _plugins.firstWhere(
              (p) => p.settings.runtimeType.toString() == entry.key,
            );
            plugin.settings!.fromJson(entry.value);
            newSettings[plugin.settings.runtimeType] = plugin.settings!;
          } catch (e) {
            print('Error loading settings for $entry: $e');
          }
        }

        state = state.copyWith(pluginSettings: newSettings);
      }
    } catch (e) {
      print('Error loading settings: $e');
    }
  }
}

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
    required bool Function(WidgetRef) canExecute,
  }) : _execute = execute,
       _canExecute = canExecute;

  @override
  Future<void> execute(WidgetRef ref) => _execute(ref);

  @override
  bool canExecute(WidgetRef ref) => _canExecute(ref);
}

enum CommandPosition { appBar, pluginToolbar, both, hidden }

class CommandState {
  final List<String> appBarOrder;
  final List<String> pluginToolbarOrder;
  final List<String> hiddenOrder;
  final Map<String, Set<String>> commandSources;

  const CommandState({
    this.appBarOrder = const [],
    this.pluginToolbarOrder = const [],
    this.hiddenOrder = const [],
    this.commandSources = const {},
  });

  CommandState copyWith({
    List<String>? appBarOrder,
    List<String>? pluginToolbarOrder,
    List<String>? hiddenOrder,
    Map<String, Set<String>>? commandSources,
  }) {
    return CommandState(
      appBarOrder: appBarOrder ?? this.appBarOrder,
      pluginToolbarOrder: pluginToolbarOrder ?? this.pluginToolbarOrder,
      hiddenOrder: hiddenOrder ?? this.hiddenOrder,
      commandSources: commandSources ?? this.commandSources,
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
      default:
        return [];
    }
  }
}

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
        // Handle both position if needed
        break;
    }
    _saveToPrefs();
  }

  void _initializeCommands(Set<EditorPlugin> plugins) async {
    // Merge commands from core and plugins
    final allCommands = [
      ..._coreCommands,
      ...plugins.expand((p) => p.getCommands()),
    ];

    for (final cmd in allCommands) {
      // Group by command ID
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
    await _loadFromPrefs(
      plugins,
    ); // Load saved positions after merging commands
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
      case CommandPosition.both: // Handle both case
        newAppBar.add(commandId);
        newPluginToolbar.add(commandId);
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

    // Merge saved positions with default positions for new commands
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

// --------------------
//   Toolbar Widgets
// --------------------

bool _shouldShowCommand(Command cmd, String? currentPlugin) {
  // Always show core commands
  if (cmd.sourcePlugin == 'Core') return true;
  // Show plugin-specific commands only when their plugin is active
  return cmd.sourcePlugin == currentPlugin;
}

class AppBarCommands extends ConsumerWidget {
  const AppBarCommands({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(appBarCommandsProvider);

    return Row(
      children: commands.map((cmd) => CommandButton(command: cmd)).toList(),
    );
  }
}

class BottomToolbar extends ConsumerWidget {
  const BottomToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = ref.watch(bottomToolbarScrollProvider);
    final commands = ref.watch(pluginToolbarCommandsProvider);

    return Container(
      height: 48,
      color: Colors.grey[900],
      child: ListView.builder(
        key: const PageStorageKey<String>('bottomToolbarScrollPosition'),
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: commands.length,
        itemBuilder:
            (context, index) =>
                CommandButton(command: commands[index], showLabel: true),
      ),
    );
  }
}

class CommandButton extends ConsumerWidget {
  final Command command;
  final bool showLabel;

  const CommandButton({
    super.key,
    required this.command,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = command.canExecute(ref);

    return IconButton(
      icon: command.icon,
      onPressed: isEnabled ? () => command.execute(ref) : null,
      tooltip: showLabel ? null : command.label,
    );
  }
}