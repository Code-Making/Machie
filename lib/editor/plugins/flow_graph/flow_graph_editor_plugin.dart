// FILE: lib/editor/plugins/flow_graph/flow_graph_editor_plugin.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/command/command_models.dart';
import 'package:machine/editor/models/editor_plugin_models.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/asset_cache/asset_models.dart';

import 'asset/flow_loaders.dart';
import 'flow_graph_editor_tab.dart';
import 'flow_graph_editor_widget.dart';
import 'models/flow_graph_models.dart';
import '../../../data/cache/type_adapters.dart';
import 'flow_graph_settings_model.dart';
import 'widgets/flow_graph_settings_widget.dart';
import '../../services/editor_service.dart';
import '../../tab_metadata_notifier.dart';
import '../../../command/command_widgets.dart';

class FlowGraphEditorPlugin extends EditorPlugin {
  static const String pluginId = 'com.machine.flow_graph';

  @override
  String get id => pluginId;

  @override
  String get name => 'Flow Graph';

  @override
  Widget get icon => const Icon(Icons.hub_outlined);

  @override
  int get priority => 10;

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  // --- Asset Management ---
  
    @override
  PluginSettings? get settings => FlowGraphSettings();

  @override
  Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) =>
      FlowGraphSettingsWidget(
        settings: settings as FlowGraphSettings,
        onChanged: onChanged,
      );

  
  @override
  List<AssetLoader> get assetLoaders => [
    FlowSchemaLoader(),
    // FlowGraphLoader is removed from here as we load content via EditorService/createTab
    // unless we want to support nested graphs as assets later.
  ];

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.toLowerCase().endsWith('.fg');
  }

  // --- Tab Creation ---

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    final content = (initData.initialContent as EditorContentString).content;
    final graph = FlowGraph.deserialize(content);

    return FlowGraphEditorTab(
      plugin: this,
      id: id,
      initialGraph: graph,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return FlowGraphEditorWidget(
      key: (tab as FlowGraphEditorTab).editorKey,
      tab: tab,
    );
  }
  
  @override
  Widget buildToolbar(WidgetRef ref) {
    return const BottomToolbar();
  }


  // --- Commands (Toolbar) ---

  @override
  List<Command> getCommands() {
    return [
      // --- Standard Save Commands ---
      BaseCommand(
        id: 'flow_save',
        label: 'Save',
        icon: const Icon(Icons.save),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async => ref.read(editorServiceProvider).saveCurrentTab(),
        canExecute: (ref) {
          final tabId = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.id));
          if (tabId == null) return false;
          // Only enable if dirty
          return ref.watch(tabMetadataProvider.select((m) => m[tabId]))?.isDirty ?? false;
        },
      ),
      BaseCommand(
        id: 'flow_save_as',
        label: 'Save As...',
        icon: const Icon(Icons.save_as),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async => ref.read(editorServiceProvider).saveCurrentTabAs(),
      ),

      // --- Graph Specific Commands ---
      BaseCommand(
        id: 'flow_link_schema',
        label: 'Link Schema',
        icon: const Icon(Icons.link),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async {
          await _getEditorState(ref)?.linkSchema();
        },
      ),
      BaseCommand(
        id: 'flow_add_node',
        label: 'Add Node',
        icon: const Icon(Icons.add_box_outlined),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async {
          _getEditorState(ref)?.togglePalette();
        },
      ),
      
      // --- Undo/Redo ---
      BaseCommand(
        id: 'flow_undo',
        label: 'Undo',
        icon: const Icon(Icons.undo),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.undo(),
        canExecute: (ref) {
           // Ideally check notifier.canUndo, but requires exposing state via provider
           return true; 
        }
      ),
      BaseCommand(
        id: 'flow_redo',
        label: 'Redo',
        icon: const Icon(Icons.redo),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.redo(),
        canExecute: (ref) {
           return true; 
        }
      ),
    ];
  }

  FlowGraphEditorWidgetState? _getEditorState(WidgetRef ref) {
    final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (tab is FlowGraphEditorTab) {
      return tab.editorKey.currentState;
    }
    return null;
  }

  @override
  String? get hotStateDtoType => null;
  @override
  Type? get hotStateDtoRuntimeType => null;
  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => null;
}