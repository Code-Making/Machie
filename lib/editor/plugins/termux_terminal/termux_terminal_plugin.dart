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

// Placeholder for Phase 4 widget
class PlaceholderTerminalWidget extends EditorWidget {
  const PlaceholderTerminalWidget({required super.tab, required super.key});
  @override
  ConsumerState<PlaceholderTerminalWidget> createState() => _PlaceholderState();
}

class _PlaceholderState extends EditorWidgetState<PlaceholderTerminalWidget> implements TermuxTerminalWidgetState {
  @override
  void init() {}
  @override
  void onFirstFrameReady() {
    // Notify the system that the tab is ready
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }
  @override
  void syncCommandContext() {}
  @override
  void undo() {}
  @override
  void redo() {}
  @override
  Future<EditorContent> getContent() async => EditorContentString('');
  @override
  void onSaveSuccess(String newHash) {}
  @override
  Future<TabHotStateDto?> serializeHotState() async => null;
  
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("Termux Terminal (UI Phase 4)"));
  }
}

class TermuxTerminalPlugin extends EditorPlugin {
  static const String pluginId = 'com.machine.termux_terminal';
  static const String hotStateId = 'com.machine.termux_terminal_state';

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
    // In Phase 4, we will return the actual TermuxTerminalWidget
    // For now, we return a generic placeholder that satisfies the type system
    return PlaceholderTerminalWidget(
      key: (tab as TermuxTerminalTab).editorKey, 
      tab: tab
    );
  }

  @override
  Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) {
    // Basic settings UI implementation
    final current = settings as TermuxTerminalSettings;
    return Column(
      children: [
        TextFormField(
          initialValue: current.fontSize.toString(),
          decoration: const InputDecoration(labelText: 'Font Size'),
          keyboardType: TextInputType.number,
          onChanged: (val) {
            final size = double.tryParse(val);
            if (size != null) {
              onChanged(current.copyWith(fontSize: size));
            }
          },
        ),
        TextFormField(
          initialValue: current.termuxWorkDir,
          decoration: const InputDecoration(labelText: 'Working Directory'),
          onChanged: (val) => onChanged(current.copyWith(termuxWorkDir: val)),
        ),
      ],
    );
  }
}