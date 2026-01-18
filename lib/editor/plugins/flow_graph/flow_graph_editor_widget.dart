// FILE: lib/editor/plugins/flow_graph/flow_graph_editor_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/models/editor_command_context.dart'; // Import for provider
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/widgets/dialogs/folder_picker_dialog.dart';

import 'asset/flow_asset_models.dart';
import 'flow_graph_editor_tab.dart';
import 'flow_graph_notifier.dart';
import 'flow_graph_command_context.dart'; // NEW Import
import 'widgets/flow_graph_canvas.dart';
import 'widgets/node_palette.dart';

class FlowGraphEditorWidget extends EditorWidget {
  @override
  final FlowGraphEditorTab tab;

  const FlowGraphEditorWidget({required super.key, required this.tab})
      : super(tab: tab);

  @override
  FlowGraphEditorWidgetState createState() => FlowGraphEditorWidgetState();
}

class FlowGraphEditorWidgetState extends EditorWidgetState<FlowGraphEditorWidget> {
  late final FlowGraphNotifier _notifier;
  
  // NEW: Expose notifier for Plugin commands
  FlowGraphNotifier get notifier => _notifier;

  bool _isPaletteVisible = false;
  Set<AssetQuery> _requiredAssetQueries = {};

  @override
  void init() {
    _notifier = FlowGraphNotifier(widget.tab.initialGraph);
    _notifier.addListener(_onGraphChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateAssetDependencies();
      syncCommandContext(); // Initial sync
    });
  }

  @override
  void onFirstFrameReady() {
    if (mounted && !widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  void _updateAssetDependencies() {
    if (!mounted) return;

    final project = ref.read(appNotifierProvider).value?.currentProject;
    final repo = ref.read(projectRepositoryProvider);
    final tabMetadata = ref.read(tabMetadataProvider)[widget.tab.id];

    if (project == null || repo == null || tabMetadata == null) return;

    final contextPath = repo.fileHandler.getPathForDisplay(
      tabMetadata.file.uri,
      relativeTo: project.rootUri,
    );

    final newQueries = <AssetQuery>{};
    
    final schemaPath = _notifier.graph.schemaPath;
    if (schemaPath != null && schemaPath.isNotEmpty) {
      newQueries.add(AssetQuery(
        path: schemaPath,
        mode: AssetPathMode.relativeToContext,
        contextPath: contextPath,
      ));
    }

    if (!const SetEquality().equals(newQueries, _requiredAssetQueries)) {
      _requiredAssetQueries = newQueries;
      ref.read(assetMapProvider(widget.tab.id).notifier).updateUris(newQueries);
    }
  }

  void _onGraphChanged() {
    ref.read(editorServiceProvider).markCurrentTabDirty();
    _updateAssetDependencies();
    syncCommandContext(); // Update selection state in toolbar
    setState(() {});
  }

  void togglePalette() {
    setState(() => _isPaletteVisible = !_isPaletteVisible);
  }

  Future<void> linkSchema() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    final repo = ref.read(projectRepositoryProvider);
    final metadata = ref.read(tabMetadataProvider)[widget.tab.id];

    if (project == null || repo == null || metadata == null) return;

    final parentUri = repo.fileHandler.getParentUri(metadata.file.uri);
    
    final selectedPath = await showDialog<String>(
      context: context,
      builder: (_) => FileOrFolderPickerDialog(initialUri: parentUri),
    );

    if (selectedPath == null) return;

    final contextPath = repo.fileHandler.getPathForDisplay(
      metadata.file.uri, 
      relativeTo: project.rootUri
    );
    
    final relativeToGraph = repo.calculateRelativePath(contextPath, selectedPath);

    _notifier.setSchemaPath(relativeToGraph);
  }

  // NEW: Implement SyncCommandContext
  @override
  void syncCommandContext() {
    final hasSelection = _notifier.selectedNodeIds.isNotEmpty;
    
    ref.read(commandContextProvider(widget.tab.id).notifier).state = 
      FlowGraphCommandContext(hasSelection: hasSelection);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(assetMapProvider(widget.tab.id));

    FlowSchemaAssetData? schemaData;
    final schemaPath = _notifier.graph.schemaPath;
    
    if (schemaPath != null) {
      final project = ref.watch(appNotifierProvider).value?.currentProject;
      final repo = ref.watch(projectRepositoryProvider);
      final metadata = ref.watch(tabMetadataProvider)[widget.tab.id];

      if (project != null && repo != null && metadata != null) {
        final contextPath = repo.fileHandler.getPathForDisplay(
          metadata.file.uri, 
          relativeTo: project.rootUri
        );
        
        final query = AssetQuery(
          path: schemaPath,
          mode: AssetPathMode.relativeToContext,
          contextPath: contextPath,
        );

        final asset = ref.watch(resolvedAssetProvider(
          ResolvedAssetRequest(tabId: widget.tab.id, query: query)
        ));
        
        if (asset is FlowSchemaAssetData) {
          schemaData = asset;
        }
      }
    }

    return Stack(
      children: [
        FlowGraphCanvas(
          notifier: _notifier,
          schemaMap: schemaData?.typeMap ?? {},
          // Assuming settings are passed here from Phase 4 update (omitted for brevity, assume passed or defaults)
          settings: ref.watch(
            package:machine/settings/settings_notifier.dart:effectiveSettingsProvider
            .select((s) => s.pluginSettings[package:machine/editor/plugins/flow_graph/flow_graph_settings_model.dart:FlowGraphSettings] as package:machine/editor/plugins/flow_graph/flow_graph_settings_model.dart:FlowGraphSettings?)
          ) ?? package:machine/editor/plugins/flow_graph/flow_graph_settings_model.dart:FlowGraphSettings(), 
        ),

        if (_isPaletteVisible && schemaData != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 250,
            child: NodePalette(
              schema: schemaData,
              onNodeSelected: (type) {
                final center = _notifier.graph.viewportPosition * -1 + const Offset(400, 300);
                _notifier.addNode(type.type, center);
                togglePalette();
              },
              onClose: togglePalette,
            ),
          ),
          
        if (_isPaletteVisible && schemaData == null)
           Positioned(
            right: 10,
            top: 50,
            child: Material(
              color: Colors.red.shade900,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("No Schema Loaded.\nLink a flow_schema.json via toolbar.", style: TextStyle(color: Colors.white)),
              ),
            ),
           )
      ],
    );
  }

  @override
  void undo() => _notifier.undo();

  @override
  void redo() => _notifier.redo();

  @override
  Future<EditorContent> getContent() async {
    return EditorContentString(_notifier.graph.serialize());
  }

  @override
  void onSaveSuccess(String newHash) {}

  @override
  Future<TabHotStateDto?> serializeHotState() async => null;

  @override
  void dispose() {
    _notifier.removeListener(_onGraphChanged);
    _notifier.dispose();
    super.dispose();
  }
}