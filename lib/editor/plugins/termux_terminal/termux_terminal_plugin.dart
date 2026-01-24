// FILE: lib/editor/plugins/termux_terminal/termux_terminal_plugin.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  // Define a unique position for the terminal's toolbar
  static const CommandPosition termuxToolbar = CommandPosition(
    id: 'com.machine.termux_terminal.toolbar',
    label: 'Termux Toolbar',
    icon: Icons.build_circle_outlined,
  );

  // Define a unique position for the terminal's toolbar
  static const CommandPosition termuxToolbar = CommandPosition(
    id: 'com.machine.termux_terminal.toolbar',
    label: 'Termux Toolbar',
    icon: Icons.build_circle_outlined,
  );

  // ... (id, name, icon, priority, settings, etc. remain the same) ...

  @override
  List<CommandPosition> getCommandPositions() {
    return [termuxToolbar];
  }


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
  PluginDataRequirement get dataRequirement => PluginDataRequirement.none;

  @override
  String? get hotStateDtoType => hotStateId;

  @override
  Type? get hotStateDtoRuntimeType => TermuxHotStateDto;

  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => TermuxHotStateAdapter();

  @override
  bool supportsFile(DocumentFile file) {
    // Supports specific ".termux" files or virtual files for sessions
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

    // Restore state if available
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
    // Return the actual TermuxTerminalWidget now
    return TermuxTerminalWidget(
      key: (tab as TermuxTerminalTab).editorKey,
      tab: tab,
    );
  }

  // ADD the buildToolbar method
  @override
  Widget buildToolbar(WidgetRef ref) {
    // Return the custom toolbar for this plugin
    return const TermuxTerminalToolbar();
  }
  
  // REPLACE the buildSettingsUI method with the actual settings widget


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