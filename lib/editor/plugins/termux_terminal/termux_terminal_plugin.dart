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
import 'widgets/termux_settings_widget.dart';
import '../../../command/command_widgets.dart';

class TermuxTerminalPlugin extends EditorPlugin {
  static const String pluginId = 'com.machine.termux_terminal';
  static const String hotStateId = 'com.machine.termux_terminal_state';
  static const String termuxSessionUri = 'internal://termux.terminal';

  // We reuse the standard plugin toolbar position (bottom bar)
  // This ID maps to AppCommandPositions.pluginToolbar
  static const CommandPosition termuxToolbar = AppCommandPositions.pluginToolbar;

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
    // We don't need to define a *new* position, we just use the app's default pluginToolbar.
    return [AppCommandPositions.pluginToolbar];
  }

  // --- COMMAND IMPLEMENTATION ---

  /// Helper to get the active terminal state
  TermuxTerminalWidgetState? _getActiveTerminalState(WidgetRef ref) {
    final activeTab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (activeTab is TermuxTerminalTab) {
      return activeTab.editorKey.currentState;
    }
    return null;
  }

  @override
  List<Command> getCommands() {
    final termuxSettings = settings as TermuxTerminalSettings;
    
    // 1. Standard Terminal Keys
    final standardCommands = [
      BaseCommand(
        id: 'termux_esc',
        label: 'Esc',
        icon: const Icon(Icons.keyboard_return), // Visual approx for Esc
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b'),
      ),
      BaseCommand(
        id: 'termux_tab',
        label: 'Tab',
        icon: const Icon(Icons.keyboard_tab),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\t'),
      ),
      BaseCommand(
        id: 'termux_ctrl',
        label: 'Ctrl (Toggle)',
        icon: const Icon(Icons.keyboard_control_key),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.toggleCtrl(),
      ),
      BaseCommand(
        id: 'termux_alt',
        label: 'Alt (Toggle)',
        icon: const Icon(Icons.alt_route),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.toggleAlt(),
      ),
      BaseCommand(
        id: 'termux_arrow_up',
        label: 'Up',
        icon: const Icon(Icons.arrow_upward),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b[A'),
      ),
      BaseCommand(
        id: 'termux_arrow_down',
        label: 'Down',
        icon: const Icon(Icons.arrow_downward),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b[B'),
      ),
      BaseCommand(
        id: 'termux_ctrl_c',
        label: 'Ctrl+C',
        icon: const Icon(Icons.cancel), 
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x03'),
      ),
      BaseCommand(
        id: 'termux_ctrl_x',
        label: 'Ctrl+X',
        icon: const Icon(Icons.cut),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x18'),
      ),
    ];

    // 2. Dynamic Commands from Settings
    final customCommands = termuxSettings.customShortcuts.asMap().entries.map((entry) {
      final index = entry.key;
      final shortcut = entry.value;
      
      return BaseCommand(
        id: 'termux_custom_$index',
        label: shortcut.label,
        icon: Icon(TerminalShortcut.resolveIcon(shortcut.iconName)),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async {
          // Send command followed by newline
          _getActiveTerminalState(ref)?.sendRawInput('${shortcut.command}\r');
        },
      );
    }).toList();

    return [...standardCommands, ...customCommands];
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
          return ref.watch(appNotifierProvider).value?.currentProject != null;
        },
        execute: (ref) async {
          final notifier = ref.read(appNotifierProvider.notifier);
          final terminalFile = VirtualDocumentFile(
            uri: termuxSessionUri,
            name: 'Termux Session',
          );
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
    return file.uri == termuxSessionUri;
  }

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    String? history;
    String? cachedWd;

    if (initData.hotState is TermuxHotStateDto) {
      final state = initData.hotState as TermuxHotStateDto;
      cachedWd = state.workingDirectory;
      history = state.terminalHistory;
    }

    return TermuxTerminalTab(
      plugin: this,
      initialWorkingDirectory: cachedWd ?? '', 
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
  Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) {
    return TermuxSettingsWidget(
      settings: settings as TermuxTerminalSettings,
      onChanged: (newSettings) => onChanged(newSettings as PluginSettings),
    );
  }
  @override
  Widget buildToolbar(WidgetRef ref) {
    return const BottomToolbar();
  }
}