// =========================================
// UPDATED: lib/command/command_widgets.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_notifier.dart';
import '../command/command_models.dart';
import 'command_notifier.dart';
import '../editor/services/text_editing_capability.dart';

// REFACTORED: A generic provider family to get commands for any position.
final commandsForPositionProvider = Provider.family<List<dynamic>, String>((
  ref,
  positionId,
) {
  final commandState = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPlugin = ref.watch(
    appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab?.plugin,
    ),
  );

  final visibleItems = <dynamic>[];
  final order = commandState.orderedCommandsByPosition[positionId] ?? [];

  for (final id in order) {
    if (commandState.commandGroups.containsKey(id)) {
      visibleItems.add(commandState.commandGroups[id]!);
      continue;
    }

    // v-- THIS IS THE CORRECTED LOGIC --v
    final command = notifier.allRegisteredCommands.firstWhereOrNull((c) {
      // The command ID from the registry MUST match the ID from our ordered list.
      if (c.id != id) {
        return false;
      }

      // Now that we have the correct command, check if it's valid in the current context.
      // Condition 1: It's an app-level command.
      if (c.sourcePlugin == 'App') return true;
      
      // Condition 2: It's a generic text command and the ACTIVE PLUGIN is a TextEditablePlugin.
      if (c is BaseTextEditableCommand && currentPlugin is TextEditablePlugin) {
        return true;
      }
      
      // Condition 3: The command's source matches the currently active plugin's ID.
      return c.sourcePlugin == currentPlugin?.id;
    });
    // ^-- END OF CORRECTION --^
    
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

return Focus(
      canRequestFocus: false,
      child: IconButton(
        icon: command.icon,
        onPressed: isEnabled ? () => command.execute(ref) : null,
        tooltip: command.label,
      ),
    );
  }
}

class CommandGroupButton extends ConsumerStatefulWidget {
  final CommandGroup commandGroup;

  const CommandGroupButton({super.key, required this.commandGroup});

  @override
  ConsumerState<CommandGroupButton> createState() => _CommandGroupButtonState();
}

class _CommandGroupButtonState extends ConsumerState<CommandGroupButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _hideMenu(); // Ensure the overlay is removed when the widget is disposed
    super.dispose();
  }

  /// Toggles the visibility of the custom menu overlay.
  void _toggleMenu() {
    if (_overlayEntry != null) {
      _hideMenu();
    } else {
      _showMenu();
    }
  }

  /// Removes the menu overlay from the screen.
  void _hideMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
  
  void _handleCommandExecution(Command command) {
    _hideMenu();
    // Check if enabled before executing
    if (command.canExecute(ref)) {
      command.execute(ref);
    }
  }

  /// Creates and displays the custom menu overlay.
  void _showMenu() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject()! as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    final alignRight = (offset.dx + size.width / 2) > screenSize.width / 2;
    final openUpwards = (offset.dy + size.height / 2) > screenSize.height / 2;

    final Alignment followerAnchor = openUpwards
        ? (alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
        : (alignRight ? Alignment.topRight : Alignment.topLeft);
        
    final Alignment targetAnchor = openUpwards
        ? (alignRight ? Alignment.topRight : Alignment.topLeft)
        : (alignRight ? Alignment.bottomRight : Alignment.bottomLeft);
        
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final commandsInGroup = _getCommandsInGroup(ref);
        if (commandsInGroup.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _hideMenu());
          return const SizedBox.shrink();
        }
        
        // ================== THE FINAL REFINEMENT ==================
        Widget menuBody;

        if (widget.commandGroup.showLabels) {
          // CASE 1: Labels are shown. We need IntrinsicWidth to measure the
          // widest ListTile and ensure all tiles have the same width and
          // a full-width tappable area.
          menuBody = IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: commandsInGroup.map((command) {
                final isEnabled = command.canExecute(ref);
                return ListTile(
                  dense: true,
                  enabled: isEnabled,
                  leading: command.icon,
                  title: Text(command.label),
                  onTap: () => _handleCommandExecution(command),
                );
              }).toList(),
            ),
          );
        } else {
          // CASE 2: Icon-only. IntrinsicWidth is unnecessary here. A simple
          // Column of IconButtons will naturally have the correct, compact width.
          menuBody = Column(
            mainAxisSize: MainAxisSize.min,
            children: commandsInGroup.map((command) {
              final isEnabled = command.canExecute(ref);
              return IconButton(
                icon: command.icon,
                tooltip: command.label,
                onPressed: isEnabled
                    ? () => _handleCommandExecution(command)
                    : null,
              );
            }).toList(),
          );
        }
        // ==========================================================

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _hideMenu,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              followerAnchor: followerAnchor,
              targetAnchor: targetAnchor,
              offset: Offset(0, openUpwards ? -4.0 : 4.0),
              child: Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(4.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: Padding(
                    // Add a bit more padding for the icon-only version
                    padding: EdgeInsets.symmetric(
                      vertical: 4.0,
                      horizontal: widget.commandGroup.showLabels ? 0.0 : 4.0,
                    ),
                    child: menuBody, // Use the conditionally built menu body
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  /// Helper to get the list of valid commands for the current context.
  List<Command> _getCommandsInGroup(WidgetRef ref) {
    final notifier = ref.read(commandProvider.notifier);
    final currentPluginId = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab?.plugin.id,
      ),
    );

    return widget.commandGroup.commandIds
        .map(
          (id) => notifier.allRegisteredCommands.firstWhereOrNull(
            (c) =>
                c.id == id &&
                (c.sourcePlugin == currentPluginId || c.sourcePlugin == 'App'),
          ),
        )
        .whereType<Command>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // Check if there are any executable commands in the group for the current context.
    final commandsInGroup = _getCommandsInGroup(ref);
    if (commandsInGroup.isEmpty) {
      return const SizedBox.shrink();
    }

    // This widget links the button's position to the LayerLink.
    final button = CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        icon: widget.commandGroup.icon,
        tooltip: widget.commandGroup.label,
        onPressed: _toggleMenu,
      ),
    );

    // This is the same wrapping logic from the original implementation.
    final currentPlugin = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab?.plugin,
      ),
    );

    if (currentPlugin != null) {
      return currentPlugin.wrapCommandToolbar(button);
    }
    return button;
  }
}
