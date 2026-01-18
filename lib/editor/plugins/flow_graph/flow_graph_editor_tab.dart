// FILE: lib/editor/plugins/flow_graph/flow_graph_editor_tab.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/editor_tab_models.dart';
import 'flow_graph_editor_widget.dart';

class FlowGraphEditorTab extends EditorTab {
  @override
  final GlobalKey<FlowGraphEditorWidgetState> editorKey;

  FlowGraphEditorTab({
    required super.plugin,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<FlowGraphEditorWidgetState>();

  @override
  void dispose() {
    // Cleanup logic if needed
  }
}