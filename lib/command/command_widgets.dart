// lib/command/command_widgets.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart'; // REFACTOR: Import for TapRegion

import '../app/app_notifier.dart';
import '../editor/plugins/code_editor/code_editor_plugin.dart';
import 'command_notifier.dart';

// ... (appBarCommandsProvider and pluginToolbarCommandsProvider are unchanged) ...
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
    if (commandState.commandGroups.containsKey(id)) {
      visibleItems.add(commandState.commandGroups[id]!);
      continue;
    }
    final command = notifier.allRegisteredCommands.firstWhereOrNull(
      (c) =>
          c.id == id &&
          (c.sourcePlugin == currentPluginName || c.sourcePlugin == 'App'),
    );
    if (command != null) {
      visibleItems.add(command);
    }
  }
  return visibleItems;
});
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
    if (commandState.commandGroups.containsKey(id)) {
      visibleItems.add(commandState.commandGroups[id]!);
      continue;
    }
    final command = notifier.allRegisteredCommands.firstWhereOrNull(
      (c) =>
          c.id == id &&
          (c.sourcePlugin == currentPluginName || c.sourcePlugin == 'App'),
    );
    if (command != null) {
      visibleItems.add(command);
    }
  }
  return visibleItems;
});


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

    final items = ref.watch(appBarCommandsProvider);
    final currentPlugin = ref.watch(appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab?.plugin,
    ));

    final commandRow = Row(
      children: items.map((item) {
        if (item is Command) {
          return CommandButton(command: item);
        }
        if (item is CommandGroup) {
          return CommandGroupButton(commandGroup: item);
        }
        return const SizedBox.shrink();
      }).toList(),
    );

    // REFACTOR: Conditionally wrap in TapRegion
    if (currentPlugin is CodeEditorPlugin) {
      return CodeEditorTapRegion(child: commandRow);
    }
    return commandRow;
  }
}

class BottomToolbar extends ConsumerStatefulWidget {
  const BottomToolbar({super.key});

  @override
  ConsumerState<BottomToolbar> createState() => _BottomToolbarState();
}

class _BottomToolbarState extends ConsumerState<BottomToolbar> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final override = ref.watch(
      appNotifierProvider.select((s) => s.value?.bottomToolbarOverride),
    );
    if (override != null) {
      return override;
    }

    final items = ref.watch(pluginToolbarCommandsProvider);
    final currentPlugin = ref.watch(appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab?.plugin,
    ));

    final listView = ListView.builder(
      key: const PageStorageKey<String>('bottomToolbarScrollPosition'),
      controller: _scrollController,
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
    );

    final container = Container(
      height: 48,
      color: Theme.of(context).bottomAppBarTheme.color,
      child: currentPlugin is CodeEditorPlugin
          ? CodeEditorTapRegion(child: listView)
          : listView,
    );

    return container;
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

// REFACTOR: Replaced PopupMenuButton with a custom DropdownButton implementation.
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

    final commandsInGroup = commandGroup.commandIds
        .map((id) => notifier.allRegisteredCommands.firstWhereOrNull(
              (c) =>
                  c.id == id &&
                  (c.sourcePlugin == currentPluginName || c.sourcePlugin == 'App'),
            ))
        .whereType<Command>()
        .toList();

    if (commandsInGroup.isEmpty) {
      return const SizedBox.shrink();
    }

    // This is a dummy value for the dropdown to show the icon.
    // We use a list with a single null value to represent the button itself.
    final List<Command?> dropdownItems = [null, ...commandsInGroup];

    final dropdown = DropdownButton<Command>(
      // A key is important for DropdownButtons when their items change.
      key: ValueKey(commandGroup.id),
      // The value is always null because we want to show the icon, not a selected item.
      value: null,
      // The icon displayed on the button.
      icon: commandGroup.icon,
      // Hide the default underline.
      underline: const SizedBox.shrink(),
      // The tooltip for the button.
      hint: Tooltip(
        message: commandGroup.label,
        child: const SizedBox(), // Tooltip needs a child.
      ),
      // When an item is selected from the dropdown menu.
      onChanged: (Command? command) {
        command?.execute(ref);
      },
      // Build the items for the dropdown menu.
      items: dropdownItems.map((Command? command) {
        if (command == null) {
          // This creates the non-selectable header in the dropdown.
          return DropdownMenuItem<Command>(
            enabled: false,
            child: Text(
              commandGroup.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }
        // This creates a standard, selectable item.
        return DropdownMenuItem<Command>(
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
      }).toList(),
      // Use a custom builder to ensure the icon is always shown.
      selectedItemBuilder: (context) {
        return dropdownItems.map((_) => commandGroup.icon).toList();
      },
    );

    // REFACTOR: Wrap the dropdown in a CodeEditorTapRegion to preserve focus.
    return CodeEditorTapRegion(child: dropdown);
  }
}