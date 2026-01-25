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
import 'flow_graph_command_context.dart';
import '../../models/editor_command_context.dart';
import 'widgets/flow_graph_export_dialog.dart'; // Import the new dialog

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
    FlowGraphLoader(), // FIX: Add FlowGraphLoader to assetLoaders
  ];

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.toLowerCase().endsWith('.fg');
  }


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



  @override
  List<Command> getCommands(Ref ref) {
    return [
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
          return ref.watch(tabMetadataProvider.select((m) => m[tabId]))?.isDirty ?? false;
        },
      ),
      
      // NEW: Export Command
      BaseCommand(
        id: 'flow_export',
        label: 'Export Graph',
        icon: const Icon(Icons.output),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async {
          final editor = _getEditorState(ref);
          if (editor?.mounted == true) {
            await showDialog(
              context: editor!.context,
              builder: (_) => FlowGraphExportDialog(
                tabId: editor.widget.tab.id,
                notifier: editor.notifier,
              ),
            );
          }
        },
      ),
      
      BaseCommand(
        id: 'flow_delete',
        label: 'Delete',
        icon: const Icon(Icons.delete_outline),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.notifier.deleteSelection(),
        canExecute: (ref) {
           final ctx = ref.watch(activeCommandContextProvider);
           return ctx is FlowGraphCommandContext && ctx.hasSelection;
        }
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
      
      BaseCommand(
        id: 'flow_undo',
        label: 'Undo',
        icon: const Icon(Icons.undo),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.undo(),
      ),
      BaseCommand(
        id: 'flow_redo',
        label: 'Redo',
        icon: const Icon(Icons.redo),
        defaultPositions: [AppCommandPositions.appBar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.redo(),
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