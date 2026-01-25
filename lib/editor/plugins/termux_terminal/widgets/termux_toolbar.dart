import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_notifier.dart';
import '../../../../command/command_widgets.dart';
import '../../../../command/command_models.dart';
import '../../../models/editor_tab_models.dart';
import '../termux_terminal_plugin.dart';
import '../termux_terminal_models.dart';
import 'termux_terminal_widget.dart'; // Import for casting

// Helper to get the specific state class
TermuxTerminalWidgetState? _getActiveTerminalState(WidgetRef ref) {
  final activeTab = ref.watch(
    appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab),
  );
  if (activeTab is! TermuxTerminalTab) return null;
  return activeTab.editorKey.currentState as TermuxTerminalWidgetState?;
}

// Helper to force rebuild the toolbar when the terminal state changes (optional but good for UX)
// Since the State object doesn't notify, we rely on the CommandButton interactions mostly,
// but checking the state during build time allows dynamic icons.

List<Command> _getTermuxCommands(TermuxTerminalWidgetState? state) {
  final bool isCtrl = state?.isCtrlActive ?? false;
  final bool isAlt = state?.isAltActive ?? false;

  return [
    BaseCommand(
      id: 'termux_esc',
      label: 'Esc',
      icon: const Text('Esc', style: TextStyle(fontWeight: FontWeight.bold)),
      sourcePlugin: TermuxTerminalPlugin.pluginId,
      defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
      execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b'),
    ),
    BaseCommand(
      id: 'termux_tab',
      label: 'Tab',
      icon: const Icon(Icons.keyboard_tab),
      sourcePlugin: TermuxTerminalPlugin.pluginId,
      defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
      execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\t'),
    ),
    BaseCommand(
      id: 'termux_ctrl',
      label: 'Ctrl',
      // Visual feedback: Filled icon if active
      icon: Icon(isCtrl ? Icons.check_box : Icons.check_box_outline_blank, size: 20), 
      sourcePlugin: TermuxTerminalPlugin.pluginId,
      defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
      execute: (ref) async {
        _getActiveTerminalState(ref)?.toggleCtrl();
        // Force UI refresh isn't automatic here without a state management glue,
        // but the next interaction will show it.
      },
    ),
    BaseCommand(
      id: 'termux_alt',
      label: 'Alt',
      icon: Icon(isAlt ? Icons.check_box : Icons.check_box_outline_blank, size: 20),
      sourcePlugin: TermuxTerminalPlugin.pluginId,
      defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
      execute: (ref) async => _getActiveTerminalState(ref)?.toggleAlt(),
    ),
    BaseCommand(
      id: 'termux_ctrl_x',
      label: 'Ctrl+X',
      icon: const Text('^X', style: TextStyle(fontWeight: FontWeight.bold)),
      sourcePlugin: TermuxTerminalPlugin.pluginId,
      defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
      execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x18'),
    ),
    BaseCommand(
      id: 'termux_ctrl_c',
      label: 'Ctrl+C',
      icon: const Text('^C', style: TextStyle(fontWeight: FontWeight.bold)),
      sourcePlugin: TermuxTerminalPlugin.pluginId,
      defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
      execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x03'),
    ),
    BaseCommand(
      id: 'termux_arrow_up',
      label: 'Up',
      icon: const Icon(Icons.arrow_upward),
      sourcePlugin: TermuxTerminalPlugin.pluginId,
      defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
      execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b[A'),
    ),
    BaseCommand(
      id: 'termux_arrow_down',
      label: 'Down',
      icon: const Icon(Icons.arrow_downward),
      sourcePlugin: TermuxTerminalPlugin.pluginId,
      defaultPositions: [TermuxTerminalPlugin.termuxToolbar],
      execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b[B'),
    ),
  ];
}

class TermuxTerminalToolbar extends ConsumerStatefulWidget {
  const TermuxTerminalToolbar({super.key});

  @override
  ConsumerState<TermuxTerminalToolbar> createState() => _TermuxTerminalToolbarState();
}

class _TermuxTerminalToolbarState extends ConsumerState<TermuxTerminalToolbar> {
  // To update the toolbar UI when modifiers change, we can use a periodic timer check 
  // or simply rely on the fact that setState in the parent widget might rebuild this.
  // For now, we will fetch the state directly in build.
  
  @override
  Widget build(BuildContext context) {
    final activeState = _getActiveTerminalState(ref);
    final commands = _getTermuxCommands(activeState);

    return Container(
      height: 48,
      color: Theme.of(context).bottomAppBarTheme.color,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: commands.length,
        itemBuilder: (context, index) {
          // We wrap the CommandButton in a Listener to trigger a rebuild on tap
          // so the toggle state icon updates immediately.
          return GestureDetector(
            onTap: () {
                // Wait end of frame for state update
                Future.delayed(Duration.zero, () {
                    if (mounted) setState(() {});
                });
            },
            child: CommandButton(command: commands[index]),
          );
        },
      ),
    );
  }
}