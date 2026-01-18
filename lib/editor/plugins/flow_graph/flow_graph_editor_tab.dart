// FILE: lib/editor/plugins/flow_graph/flow_graph_editor_tab.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/editor_tab_models.dart';
import 'flow_graph_editor_widget.dart';
import 'models/flow_graph_models.dart';

class FlowGraphEditorTab extends EditorTab {
  @override
  final GlobalKey<FlowGraphEditorWidgetState> editorKey;
  
  final FlowGraph initialGraph;

  FlowGraphEditorTab({
    required super.plugin,
    required this.initialGraph,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<FlowGraphEditorWidgetState>();

  @override
  void dispose() {
    // Cleanup
  }
}