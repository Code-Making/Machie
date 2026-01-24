// FILE: lib/editor/plugins/termux_terminal/termux_terminal_plugin.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../project/project_models.dart';

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

  @override
  List<Command> getAppCommands() {
    return [
      BaseCommand(
        id: 'open_termux_terminal',
        label: 'New Terminal',
        icon: const Icon(Icons.terminal),
          sourcePlugin: 'App',
        defaultPositions: [AppCommandPositions.appBar],
        canExecute: (ref) {
          final project = ref.watch(appNotifierProvider).value?.currentProject;
          return project != null;
        },
        execute: (ref) async {
          final notifier = ref.read(appNotifierProvider.notifier);
          
          // Create a virtual file to represent this terminal session.
          final terminalFile = VirtualDocumentFile(
            uri: 'termux-session://${const Uuid().v4()}', // Unique URI for each session
            name: 'Termux Session',
          );

          // Open the virtual file, explicitly telling the editor service
          await notifier.openFileInEditor(
            terminalFile,
            explicitPlugin: this,
          );
        },
      ),
    ];
  }


  @override
  bool supportsFile(DocumentFile file) {
    return file.uri.startsWith('termux-session:');
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
    final termuxTab = tab as TermuxTerminalTab;
    return TermuxTerminalWidget(
      key: termuxTab.editorKey, // This key type now matches the widget's expected key type
      tab: termuxTab
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
      onChanged: (newSettings) => onChanged(newSettings),
    );
  }
}