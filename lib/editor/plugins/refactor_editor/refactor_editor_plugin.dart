// =========================================
// UPDATED: lib/editor/plugins/refactor_editor/refactor_editor_plugin.dart
// =========================================

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../models/editor_tab_models.dart';
import '../../models/editor_plugin_models.dart';
import '../../../project/project_models.dart';
import 'refactor_editor_hot_state.dart';
import 'refactor_editor_models.dart';
import 'refactor_editor_widget.dart';

import 'refactor_editor_settings_widget.dart'; // <-- IMPORT THE NEW SETTINGS UI

const String refactorSessionUri = 'internal://refactor_session.refactor';

class RefactorEditorPlugin extends EditorPlugin {
  @override
  String get id => 'com.machine.refactor_editor';
  @override
  String get name => 'Workspace Refactor';
  @override
  Widget get icon => const Icon(Icons.find_replace);
  @override
  int get priority => 100;

  @override
  PluginSettings? get settings => RefactorSettings();

  @override
  Widget buildSettingsUI(PluginSettings settings) {
    // <-- CONNECT THE NEW UI WIDGET HERE
    return RefactorEditorSettingsUI(settings: settings as RefactorSettings);
  }

  // ... rest of the file is unchanged ...

  @override
  bool supportsFile(DocumentFile file) {
    return file is InternalAppFile && file.uri == refactorSessionUri;
  }

  @override
  List<Command> getAppCommands() {
    return [
      BaseCommand(
        id: 'workspace_refactor',
        label: 'Workspace Refactor',
        icon: const Icon(Icons.manage_search),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: 'App',
        execute: (ref) async {
          final refactorSessionFile = InternalAppFile(
            uri: refactorSessionUri,
            name: 'Workspace Refactor',
            modifiedDate: DateTime.now(),
          );
          ref
              .read(appNotifierProvider.notifier)
              .openFileInEditor(refactorSessionFile);
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

  @override
  String? get hotStateDtoType => 'com.machine.refactor_editor_state';
  @override
  Type? get hotStateDtoRuntimeType => RefactorEditorHotStateDto;
  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter =>
      RefactorEditorHotStateAdapter();
}
