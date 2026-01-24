// FILE: lib/editor/plugins/termux_terminal/widgets/termux_toolbar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../command/command_widgets.dart';
import '../../../../command/command_models.dart';
import '../../../models/editor_tab_models.dart';
import '../../../app/app_notifier.dart';
import '../termux_terminal_plugin.dart';
import '../termux_terminal_models.dart';

// Helper function to get the active terminal state
TermuxTerminalWidgetState? _getActiveTerminalState(WidgetRef ref) {
  final activeTab = ref.watch(
    appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab),
  );
  if (activeTab is! TermuxTerminalTab) return null;
  return activeTab.editorKey.currentState as TermuxTerminalWidgetState?;
}

// Command Definitions
List<Command> _getTermuxCommands() => [
      BaseCommand(
        id: 'termux_clear',
        label: 'Clear',
        icon: const Icon(Icons.clear_all),
        sourcePlugin: TermuxTerminalPlugin.pluginId,
        defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x0c'), // Ctrl+L (clear)
      ),
      BaseCommand(
        id: 'termux_ctrl_c',
        label: 'Ctrl+C',
        icon: const Text('^C'),
        sourcePlugin: TermuxTerminalPlugin.pluginId,
        defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x03'), // Ctrl+C (interrupt)
      ),
      BaseCommand(
        id: 'termux_tab',
        label: 'Tab',
        icon: const Icon(Icons.keyboard_tab),
        sourcePlugin: TermuxTerminalPlugin.pluginId,
        defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x09'), // Tab
      ),
      BaseCommand(
        id: 'termux_esc',
        label: 'Esc',
        icon: const Text('Esc'),
        sourcePlugin: TermuxTerminalPlugin.pluginId,
        defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b'), // Escape
      ),
];

// The Toolbar Widget
class TermuxTerminalToolbar extends ConsumerWidget {
  const TermuxTerminalToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This is a temporary way to register commands for the toolbar.
    // In a full implementation, these commands would be registered in the plugin's `getCommands`.
    final commands = _getTermuxCommands();

    return Container(
      height: 48,
      color: Theme.of(context).bottomAppBarTheme.color,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: commands.length,
        itemBuilder: (context, index) {
          return CommandButton(command: commands[index]);
        },
      ),
    );
  }
}