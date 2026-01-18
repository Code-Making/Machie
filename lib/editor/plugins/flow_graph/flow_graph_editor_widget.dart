// FILE: lib/editor/plugins/flow_graph/flow_graph_editor_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/editor/services/editor_service.dart';

import 'asset/flow_asset_models.dart';
import 'flow_graph_editor_tab.dart';
import 'flow_graph_notifier.dart';
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
  FlowGraphNotifier? _notifier;
  bool _isPaletteVisible = false;

  @override
  void init() {
    // Initial setup
  }

  @override
  void onFirstFrameReady() {
    if (mounted && !widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  void togglePalette() {
    setState(() => _isPaletteVisible = !_isPaletteVisible);
  }

  @override
  void syncCommandContext() {
    // TODO: Update command context for toolbar buttons (Undo/Redo availability)
  }

  @override
  Widget build(BuildContext context) {
    // 1. Resolve the URI of the file for this tab
    final metadata = ref.watch(tabMetadataProvider)[widget.tab.id];
    if (metadata == null) return const Center(child: Text("Tab Error"));

    // 2. Watch the Asset Data. 
    // This connects the AssetLoader (Phase 2) to the UI.
    // If the .fg file or the schema.json changes, this rebuilds.
    final assetState = ref.watch(assetDataProvider(metadata.file.uri));

    return assetState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, st) => Center(child: Text('Error loading graph: $err')),
      data: (assetData) {
        if (assetData is! FlowGraphAssetData) {
          return const Center(child: Text("Invalid Asset Type"));
        }

        // 3. Initialize or Update Notifier
        // Ideally, we don't recreate the notifier on every build unless the graph structure changes externally.
        // For simplicity here, we create it if null.
        // In a real app, you'd sync external changes into the existing notifier to preserve selection/viewport.
        if (_notifier == null) {
          _notifier = FlowGraphNotifier(assetData.graph);
          _notifier!.addListener(_onGraphChanged);
        }

        return Stack(
          children: [
            // The Canvas
            FlowGraphCanvas(
              notifier: _notifier!,
              schemaMap: assetData.schema?.typeMap ?? {},
            ),

            // The Palette Overlay
            if (_isPaletteVisible && assetData.schema != null)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 250,
                child: NodePalette(
                  schema: assetData.schema!,
                  onNodeSelected: (type) {
                    // Add node at center of viewport (simplified)
                    final center = _notifier!.graph.viewportPosition * -1 + const Offset(400, 300);
                    _notifier!.addNode(type.type, center);
                    togglePalette(); // Close after add
                  },
                  onClose: togglePalette,
                ),
              ),
          ],
        );
      },
    );
  }

  void _onGraphChanged() {
    // Mark tab as dirty so "Save" becomes available
    ref.read(editorServiceProvider).markCurrentTabDirty();
    setState(() {}); // Rebuild to update UI if needed
  }

  @override
  void undo() => _notifier?.undo();

  @override
  void redo() => _notifier?.redo();

  @override
  Future<EditorContent> getContent() async {
    if (_notifier == null) throw Exception("Graph not loaded");
    // Serialize the current state of the graph from the notifier
    return EditorContentString(_notifier!.graph.serialize());
  }

  @override
  void onSaveSuccess(String newHash) {
    // Handle save completion
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async => null;
  
  @override
  void dispose() {
    _notifier?.removeListener(_onGraphChanged);
    _notifier?.dispose();
    super.dispose();
  }
}