// =========================================
// NEW FILE: lib/editor/plugins/refactor_editor/refactor_editor_plugin.dart
// =========================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../command/command_models.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../editor/editor_tab_models.dart';
import '../../../editor/plugins/plugin_models.dart';
import '../../../editor/services/editor_service.dart';
import '../../../project/project_models.dart';
import 'refactor_editor_hot_state.dart';
import 'refactor_editor_models.dart';
import 'refactor_editor_widget.dart';

/// A unique URI used to identify the singleton refactor session tab.
const String refactorSessionUri = 'internal://refactor_session.refactor';

class RefactorEditorPlugin extends EditorPlugin {
  @override
  String get id => 'com.machine.refactor_editor';
  @override
  String get name => 'Workspace Refactor';
  @override
  Widget get icon => const Icon(Icons.find_replace);
  @override
  int get priority => 100; // High priority to handle its specific file.

  @override
  PluginSettings? get settings => RefactorSettings();

  @override
  Widget buildSettingsUI(PluginSettings settings) {
    // TODO: Implement the settings UI
    return const Text('Settings for supported extensions and ignored folders will be here.');
  }

  @override
  bool supportsFile(DocumentFile file) {
    // This plugin only supports the single virtual file for the session.
    return file.uri == refactorSessionUri;
  }

  @override
  List<Command> getAppCommands() {
    return [
      BaseCommand(
        id: 'workspace_refactor',
        label: 'Workspace Refactor',
        icon: const Icon(Icons.find_replace),
        defaultPositions: [AppCommandPositions.appBar], // Add to the app bar
        sourcePlugin: 'App', // An app-level command
        execute: (ref) async {
          // This command opens the virtual file, which triggers this plugin.
          ref.read(editorServiceProvider).openOrCreate(refactorSessionUri);
        },
      ),
    ];
  }

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    RefactorSessionState initialState;
    if (initData.hotState is RefactorEditorHotStateDto) {
      final hotState = initData.hotState as RefactorEditorHotStateDto;
      initialState = RefactorSessionState(
        searchTerm: hotState.searchTerm,
        replaceTerm: hotState.replaceTerm,
        isRegex: hotState.isRegex,
        isCaseSensitive: hotState.isCaseSensitive,
      );
    } else {
      initialState = const RefactorSessionState();
    }

    return RefactorEditorTab(
      plugin: this,
      initialState: initialState,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return RefactorEditorWidget(
      key: tab.editorKey as GlobalKey<RefactorEditorWidgetState>,
      tab: tab as RefactorEditorTab,
    );
  }

  // --- Hot State Caching Contract ---
  @override
  String? get hotStateDtoType => 'com.machine.refactor_editor_state';
  @override
  Type? get hotStateDtoRuntimeType => RefactorEditorHotStateDto;
  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => RefactorEditorHotStateAdapter();
}