import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_notifier.dart';
import '../data/file_handler/file_handler.dart';
import '../project/project_models.dart';
import '../session/session_models.dart';

import '../plugin/plugin_models.dart';

import 'command_models.dart';
import 'command_notifier.dart';


final appBarCommandsProvider = Provider<List<Command>>((ref) {
  final state = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  // CORRECTED: Watch the new AppNotifier for the current plugin type
  final currentPlugin = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.plugin.runtimeType.toString()));

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
  // CORRECTED: Watch the new AppNotifier
  final currentPlugin = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.plugin.runtimeType.toString()));

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