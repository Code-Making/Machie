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
import 'package:machine/editor/models/editor_command_context.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/widgets/dialogs/folder_picker_dialog.dart';
import 'package:machine/settings/settings_notifier.dart';

import 'asset/flow_asset_models.dart';
import 'flow_graph_editor_tab.dart';
import 'flow_graph_notifier.dart';
import 'flow_graph_command_context.dart';
import 'flow_graph_settings_model.dart';
import 'widgets/flow_graph_canvas.dart';
import 'widgets/node_palette.dart';
import 'core_nodes.dart'; // Import the new core nodes

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
  
  FlowGraphNotifier get notifier => _notifier;

  bool _isPaletteVisible = false;
  Set<AssetQuery> _requiredAssetQueries = {};

  @override
  void init() {
    _notifier = FlowGraphNotifier(widget.tab.initialGraph);
    _notifier.addListener(_onGraphChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateAssetDependencies();
      syncCommandContext();
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

    // The only asset dependency is the schema file from settings.
    final settings = ref.read(effectiveSettingsProvider);
    final flowSettings = settings.pluginSettings[FlowGraphSettings] as FlowGraphSettings?;
    final schemaPath = flowSettings?.schemaPath ?? '';

    final newQueries = <AssetQuery>{};
    if (schemaPath.isNotEmpty) {
      newQueries.add(AssetQuery(
        path: schemaPath,
        mode: AssetPathMode.projectRelative,
      ));
    }

    if (!const SetEquality().equals(newQueries, _requiredAssetQueries)) {
      _requiredAssetQueries = newQueries;
      ref.read(assetMapProvider(widget.tab.id).notifier).updateUris(newQueries);
    }
  }

  void _onGraphChanged() {
    ref.read(editorServiceProvider).markCurrentTabDirty();
    // No need to call _updateAssetDependencies here, as it's driven by settings, not graph content.
    syncCommandContext();
    if (mounted) {
      setState(() {});
    }
  }

  void togglePalette() {
    setState(() => _isPaletteVisible = !_isPaletteVisible);
  }

  // linkSchema is no longer needed, it's handled by settings.

  @override
  void syncCommandContext() {
    final hasSelection = _notifier.selectedNodeIds.isNotEmpty;
    
    ref.read(commandContextProvider(widget.tab.id).notifier).state = 
      FlowGraphCommandContext(hasSelection: hasSelection);
  }

  @override
  Widget build(BuildContext context) {
    // Watch settings to trigger rebuilds and asset reloads when schema path changes.
    final settings = ref.watch(effectiveSettingsProvider.select(
      (s) => s.pluginSettings[FlowGraphSettings] as FlowGraphSettings?
    )) ?? FlowGraphSettings();

    // Re-evaluate asset dependencies if settings change.
    _updateAssetDependencies();

    // === MODIFICATION START: Schema Merging Logic ===

    final schemaPath = settings.schemaPath;
    FlowSchemaAssetData? userSchemaData;
    
    // 1. Attempt to load the user-defined schema from settings
    if (schemaPath.isNotEmpty) {
      final query = AssetQuery(path: schemaPath, mode: AssetPathMode.projectRelative);
      final asset = ref.watch(resolvedAssetProvider(
        ResolvedAssetRequest(tabId: widget.tab.id, query: query)
      ));
      
      if (asset is FlowSchemaAssetData) {
        userSchemaData = asset;
      }
    }

    // 2. Combine core nodes with user-defined nodes
    final List<FlowNodeType> combinedNodes = getCoreFlowNodes();
    if (userSchemaData != null) {
      combinedNodes.addAll(userSchemaData.nodeTypes);
    }
    
    // 3. Create a final schema object for the UI
    final finalSchemaData = FlowSchemaAssetData(combinedNodes);

    // === MODIFICATION END ===

    return Stack(
      children: [
        FlowGraphCanvas(
          notifier: _notifier,
          // Use the final merged schema map
          schemaMap: finalSchemaData.typeMap, 
          settings: settings,
        ),

        if (_isPaletteVisible)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 250,
            child: NodePalette(
              // Pass the final merged schema to the palette
              schema: finalSchemaData,
              onNodeSelected: (type) {
                final center = _notifier.graph.viewportPosition * -1 + const Offset(400, 300);
                _notifier.addNode(type.type, center);
                togglePalette();
              },
              onClose: togglePalette,
            ),
          ),
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