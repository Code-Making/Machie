// =========================================
// UPDATED: lib/command/command_widgets.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_notifier.dart';
import '../command/command_models.dart';
import 'command_notifier.dart';

// REFACTORED: A generic provider family to get commands for any position.
final commandsForPositionProvider = Provider.family<List<dynamic>, String>((
  ref,
  positionId,
) {
  final commandState = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPluginId = ref.watch(
    appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab?.plugin.id,
    ),
  );

  final visibleItems = <dynamic>[];
  // Get the order for the specified position
  final order = commandState.orderedCommandsByPosition[positionId] ?? [];

  for (final id in order) {
    if (commandState.commandGroups.containsKey(id)) {
      visibleItems.add(commandState.commandGroups[id]!);
      continue;
    }
    final command = notifier.allRegisteredCommands.firstWhereOrNull(
      (c) =>
          c.id == id &&
          (c.sourcePlugin == currentPluginId || c.sourcePlugin == 'App'),
    );
    if (command != null) {
      visibleItems.add(command);
    }
  }
  return visibleItems;
});

// NEW: A generic, reusable CommandToolbar widget.
class CommandToolbar extends ConsumerWidget {
  final CommandPosition position;
  final bool showLabels;
  final Axis direction;

  const CommandToolbar({
    super.key,
    required this.position,
    this.showLabels = false,
    this.direction = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the new provider family with our position's ID.
    final items = ref.watch(commandsForPositionProvider(position.id));
    final currentPlugin = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab?.plugin,
      ),
    );

    final List<Widget> children =
        items.map((item) {
          if (item is Command) {
            return CommandButton(command: item, showLabel: showLabels);
          }
          if (item is CommandGroup) {
            return CommandGroupButton(commandGroup: item);
          }
          return const SizedBox.shrink();
        }).toList();

    Widget toolbar;
    if (direction == Axis.horizontal) {
      toolbar = Row(mainAxisSize: MainAxisSize.min, children: children);
    } else {
      toolbar = Column(mainAxisSize: MainAxisSize.min, children: children);
    }

    // Delegate wrapping to the plugin.
    if (currentPlugin != null) {
      return currentPlugin.wrapCommandToolbar(toolbar);
    }
    return toolbar;
  }
}

// REFACTORED: AppBarCommands is now a thin wrapper around CommandToolbar.
class AppBarCommands extends ConsumerWidget {
  const AppBarCommands({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(
      appNotifierProvider.select((s) => s.value?.appBarOverride),
    );
    if (override != null) {
      return override;
    }

    // Simply use the new generic toolbar.
    return const CommandToolbar(position: AppCommandPositions.appBar);
  }
}

// REFACTORED: BottomToolbar is now a thin wrapper around CommandToolbar.
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

    return Container(
      height: 48,
      color: Theme.of(context).bottomAppBarTheme.color,
      // Use a ListView to allow horizontal scrolling, wrapping the generic toolbar.
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: const [
          CommandToolbar(position: AppCommandPositions.pluginToolbar),
        ],
      ),
    );
  }
}

// ... (CommandButton and CommandGroupButton are unchanged) ...
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
    final currentPluginId = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab?.plugin.id,
      ),
    );

    final commandsInGroup =
        commandGroup.commandIds
            .map(
              (id) => notifier.allRegisteredCommands.firstWhereOrNull(
                (c) =>
                    c.id == id &&
                    (c.sourcePlugin == currentPluginId ||
                        c.sourcePlugin == 'App'),
              ),
            )
            .whereType<Command>()
            .toList();

    if (commandsInGroup.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentPlugin = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab?.plugin,
      ),
    );

    final key = GlobalKey();

    final dropdown = PopupMenuButton<Command>(
      key: key,
      icon: commandGroup.icon,
      tooltip: commandGroup.label,
      onSelected: (command) => command.execute(ref),
      itemBuilder: (BuildContext context) {
        return commandsInGroup.map((command) {
          final isEnabled = command.canExecute(ref);
          return PopupMenuItem<Command>(
            value: command,
            enabled: isEnabled,
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

    if (currentPlugin != null) {
      return currentPlugin.wrapCommandToolbar(dropdown);
    }
    return dropdown;
  }
}
