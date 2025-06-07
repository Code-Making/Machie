import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plugins/code_editor/code_editor_plugin.dart'; // For CodeEditorSettings
import '../plugins/plugin_architecture.dart'; // For EditorPlugin, PluginSettings, CommandPosition, Command


final logProvider = StateNotifierProvider<LogNotifier, List<String>>((ref) {
  final logNotifier = LogNotifier();
  // Capture the print stream when provider initializes
  final subscription = printStream.stream.listen(logNotifier.add);
  ref.onDispose(() => subscription.cancel());
  return logNotifier;
});


class LogNotifier extends StateNotifier<List<String>> {
  LogNotifier() : super([]);

  void add(String message) {
    state = [...state, '${DateTime.now().toIso8601String()}: $message'];
    if (state.length > 200) {
      state = state.sublist(state.length - 100); // Keep last 100 entries
    }
  }

  void clearLogs() {
    state = [];
  }
}

class DebugLogView extends ConsumerWidget {
  const DebugLogView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logProvider);

    return AlertDialog(
      title: const Text('Debug Logs'),
      content: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) => Text(logs[index]),
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => ref.read(logProvider.notifier).clearLogs(),
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _buildPluginSettingsList(context, ref),
    );
  }

  Widget _buildPluginSettingsList(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final settings = ref.watch(settingsProvider);

    return ListView(
      children: [
        // Add a tile for command settings
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('Command Customization'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pushNamed(context, '/command-settings'),
        ),
        // Existing plugin settings
        ...plugins
            .where((p) => p.settings != null)
            .map(
              (plugin) => _PluginSettingsCard(
                plugin: plugin,
                settings: settings.pluginSettings[plugin.settings.runtimeType]!,
              ),
            ),
      ],
    );
  }
}

class _PluginSettingsCard extends ConsumerWidget {
  final EditorPlugin plugin;
  final PluginSettings settings;

  const _PluginSettingsCard({required this.plugin, required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                plugin.icon,
                const SizedBox(width: 12),
                Text(
                  plugin.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSettingsWithErrorHandling(),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsWithErrorHandling() {
    try {
      return plugin.buildSettingsUI(settings);
    } catch (e) {
      return Text('Error loading settings: ${e.toString()}');
    }
  }
}

class CommandSettingsScreen extends ConsumerWidget {
  const CommandSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commandProvider);
    final notifier = ref.read(commandProvider.notifier);
    print(
      'Current Command State: ${state.appBarOrder} | '
      '${state.pluginToolbarOrder} | ${state.hiddenOrder}',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Command Customization')),
      body: ListView(
        shrinkWrap: true,
        children: [
          _buildSection(
            context,
            ref,
            'App Bar Commands',
            state.appBarOrder,
            CommandPosition.appBar,
          ),
          _buildSection(
            context,
            ref,
            'Plugin Toolbar Commands',
            state.pluginToolbarOrder,
            CommandPosition.pluginToolbar,
          ),
          _buildSection(
            context,
            ref,
            'Hidden Commands',
            state.hiddenOrder,
            CommandPosition.hidden,
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<String> commandIds,
    CommandPosition position,
  ) {
    final state = ref.watch(commandProvider);
    return ExpansionTile(
      title: Text(title),
      initiallyExpanded: true,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: commandIds.length,
          itemBuilder:
              (ctx, index) => _buildCommandItem(
                context,
                ref,
                commandIds[index],
                state.commandSources[commandIds[index]]!,
              ),
          onReorder:
              (oldIndex, newIndex) =>
                  _handleReorder(ref, position, oldIndex, newIndex, commandIds),
        ),
      ],
    );
  }

  Widget _buildCommandItem(
    BuildContext context,
    WidgetRef ref,
    String commandId,
    Set<String> sources,
  ) {
    final notifier = ref.read(commandProvider.notifier);
    final command = notifier.getCommand(commandId)!;

    return ListTile(
      key: ValueKey(commandId),
      leading: command.icon,
      title: Text(command.label),
      subtitle: sources.length > 1 ? Text('From: ${sources.join(', ')}') : null,
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showPositionMenu(context, ref, command),
      ),
    );
  }

  void _handleReorder(
    WidgetRef ref,
    CommandPosition position,
    int oldIndex,
    int newIndex,
    List<String> currentOrder,
  ) {
    if (oldIndex < newIndex) newIndex--;
    final item = currentOrder.removeAt(oldIndex);
    currentOrder.insert(newIndex, item);

    ref.read(commandProvider.notifier).updateOrder(position, currentOrder);
  }

  void _showPositionMenu(BuildContext context, WidgetRef ref, Command command) {
    final notifier = ref.read(commandProvider.notifier);

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('Position for ${command.label}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  CommandPosition.values
                      .map(
                        (pos) => ListTile(
                          title: Text(pos.toString().split('.').last),
                          onTap: () {
                            notifier.updateCommandPosition(command.id, pos);
                            Navigator.pop(ctx);
                          },
                        ),
                      )
                      .toList(),
            ),
          ),
    );
  }
}