// lib/command/command_widgets.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_notifier.dart';

import 'command_notifier.dart';

// This provider now resolves the correct, context-specific commands for the app bar.
final appBarCommandsProvider = Provider<List<dynamic>>((ref) {
  final commandState = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPluginName = ref.watch(
    appNotifierProvider.select(
      (s) =>
          s.value?.currentProject?.session.currentTab?.plugin.runtimeType
              .toString(),
    ),
  );

  final visibleItems = <dynamic>[];
  final order = commandState.appBarOrder;

  for (final id in order) {
    // Is it a group?
    if (commandState.commandGroups.containsKey(id)) {
      visibleItems.add(commandState.commandGroups[id]!);
      continue;
    }

    // Find the command for the current plugin context
    final command = notifier.allRegisteredCommands.firstWhereOrNull(
      (c) => c.id == id && c.sourcePlugin == currentPluginName,
    );

    if (command != null) {
      visibleItems.add(command);
    }
  }
  return visibleItems;
});

// This provider does the same for the plugin toolbar.
final pluginToolbarCommandsProvider = Provider<List<dynamic>>((ref) {
  final commandState = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPluginName = ref.watch(
    appNotifierProvider.select(
      (s) =>
          s.value?.currentProject?.session.currentTab?.plugin.runtimeType
              .toString(),
    ),
  );

  final visibleItems = <dynamic>[];
  final order = commandState.pluginToolbarOrder;

  for (final id in order) {
    // Is it a group?
    if (commandState.commandGroups.containsKey(id)) {
      visibleItems.add(commandState.commandGroups[id]!);
      continue;
    }

    // Find the command for the current plugin context
    final command = notifier.allRegisteredCommands.firstWhereOrNull(
      (c) => c.id == id && c.sourcePlugin == currentPluginName,
    );

    if (command != null) {
      visibleItems.add(command);
    }
  }
  return visibleItems;
});

final bottomToolbarScrollProvider = Provider<ScrollController>((ref) {
  return ScrollController();
});

// --------------------
//   Toolbar Widgets
// --------------------

class AppBarCommands extends ConsumerWidget {
  const AppBarCommands({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // NEW: Check for app bar override
    final override = ref.watch(
      appNotifierProvider.select((s) => s.value?.appBarOverride),
    );
    if (override != null) {
      // When overriding, we expect the plugin to provide the whole actions row
      return override;
    }

    final items = ref.watch(appBarCommandsProvider);

    return Row(
      children:
          items.map((item) {
            if (item is Command) {
              return CommandButton(command: item);
            }
            if (item is CommandGroup) {
              // CORRECTED: AppBar now knows how to render groups.
              return CommandGroupButton(commandGroup: item);
            }
            return const SizedBox.shrink();
          }).toList(),
    );
  }
}

class BottomToolbar extends ConsumerWidget {
  const BottomToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(
      appNotifierProvider.select((s) => s.value?.bottomToolbarOverride),
    );
    if (override != null) {
      return override;
    }

    final scrollController = ref.watch(bottomToolbarScrollProvider);
    final items = ref.watch(pluginToolbarCommandsProvider);

    return Container(
      height: 48,
      color: Colors.grey[900],
      child: ListView.builder(
        key: const PageStorageKey<String>('bottomToolbarScrollPosition'),
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is Command) {
            return CommandButton(command: item, showLabel: false);
          }
          if (item is CommandGroup) {
            return CommandGroupButton(commandGroup: item);
          }
          return const SizedBox.shrink();
        },
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

    if (showLabel) {
      return TextButton.icon(
        icon: command.icon,
        label: Text(command.label),
        onPressed: isEnabled ? () => command.execute(ref) : null,
      );
    }

    return IconButton(
      icon: command.icon,
      onPressed: isEnabled ? () => command.execute(ref) : null,
      tooltip: command.label,
    );
  }
}

class CommandGroupButton extends ConsumerWidget {
  final CommandGroup commandGroup;

  const CommandGroupButton({super.key, required this.commandGroup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(commandProvider.notifier);
    final currentPluginName = ref.watch(
      appNotifierProvider.select(
        (s) =>
            s.value?.currentProject?.session.currentTab?.plugin.runtimeType
                .toString(),
      ),
    );

    final commandsInGroup =
        commandGroup.commandIds
            .map(
              (id) => notifier.allRegisteredCommands.firstWhereOrNull(
                (c) => c.id == id && c.sourcePlugin == currentPluginName,
              ),
            )
            .whereType<Command>()
            .toList();

    if (commandsInGroup.isEmpty) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<Command>(
      icon: commandGroup.icon,
      tooltip: commandGroup.label,
      onSelected: (Command command) {
        command.execute(ref);
      },
      itemBuilder: (BuildContext context) {
        return commandsInGroup.map((command) {
          return PopupMenuItem<Command>(
            value: command,
            enabled: command.canExecute(ref),
            child: Row(
              children: [
                command.icon,
                const SizedBox(width: 12),
                Text(command.label),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}
