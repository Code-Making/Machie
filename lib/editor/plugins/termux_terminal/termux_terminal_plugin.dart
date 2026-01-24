// FILE: lib/editor/plugins/termux_terminal/termux_terminal_plugin.dart
// (Additions to the file from the previous phases)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Add these imports for the app command
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../project/project_models.dart'; // For VirtualDocumentFile

import '../../models/editor_plugin_models.dart';
import '../../models/editor_tab_models.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/dto/tab_hot_state_dto.dart';

import 'termux_terminal_models.dart';
import 'termux_hot_state.dart';
import 'termux_hot_state_adapter.dart';
import 'widgets/termux_terminal_widget.dart';
import 'widgets/termux_toolbar.dart';
import 'widgets/termux_settings_widget.dart';


class TermuxTerminalPlugin extends EditorPlugin {
  static const String pluginId = 'com.machine.termux_terminal';
  static const String hotStateId = 'com.machine.termux_terminal_state';

  static const CommandPosition termuxToolbar = CommandPosition(
    id: 'com.machine.termux_terminal.toolbar',
    label: 'Termux Toolbar',
    icon: Icons.build_circle_outlined,
  );

  // ... (id, name, icon, and other properties remain the same) ...
  @override
  String get id => pluginId;

  @override
  String get name => 'Termux Console';

  @override
  Widget get icon => const Icon(Icons.terminal);

  @override
  int get priority => 50;

  @override
  final PluginSettings settings = TermuxTerminalSettings();

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  String? get hotStateDtoType => hotStateId;

  @override
  Type? get hotStateDtoRuntimeType => TermuxHotStateDto;

  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => TermuxHotStateAdapter();

  @override
  List<CommandPosition> getCommandPositions() {
    return [termuxToolbar];
  }

  // --- ADD THIS METHOD ---
  @override
  List<Command> getAppCommands() {
    return [
      BaseCommand(
        id: 'open_termux_terminal',
        label: 'New Terminal',
        icon: const Icon(Icons.terminal),
        sourcePlugin: id,
        defaultPositions: [AppCommandPositions.appBar],
        canExecute: (ref) {
          // A terminal can only be opened if a project is active,
          // as it needs a working directory context.
          final project = ref.watch(appNotifierProvider).value?.currentProject;
          return project != null;
        },
        execute: (ref) async {
          final notifier = ref.read(appNotifierProvider.notifier);
          
          // Create a virtual file to represent this terminal session.
          // This allows it to be treated like any other tab in the editor.
          final terminalFile = VirtualDocumentFile(
            uri: 'termux-session://${DateTime.now().millisecondsSinceEpoch}',
            name: 'Termux Session',
          );

          // Open the virtual file, explicitly telling the editor service
          // to use this plugin.
          await notifier.openFileInEditor(
            terminalFile,
            explicitPlugin: this,
          );
        },
      ),
    ];
  }
  // --- END OF ADDED METHOD ---


  @override
  bool supportsFile(DocumentFile file) {
    return file.name.endsWith('.termux') || file.name == 'Termux Session';
  }

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    String workingDir = '/data/data/com.termux/files/home';
    String? history;

    if (initData.hotState is TermuxHotStateDto) {
      final state = initData.hotState as TermuxHotStateDto;
      workingDir = state.workingDirectory;
      history = state.terminalHistory;
    }

    return TermuxTerminalTab(
      plugin: this,
      initialWorkingDirectory: workingDir,
      initialHistory: history,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return TermuxTerminalWidget(
      key: (tab as TermuxTerminalTab).editorKey, 
      tab: tab
    );
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    return const TermuxTerminalToolbar();
  }
  
  @override
  Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) {
    return TermuxSettingsWidget(
      settings: settings as TermuxTerminalSettings,
      onChanged: (newSettings) => onChanged(newSettings as PluginSettings),
    );
  }
}