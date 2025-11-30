// lib/editor/plugins/tiled_editor/tiled_editor_models.dart

import 'package:flutter/material.dart';

import '../../../models/editor_tab_models.dart';
import 'tiled_editor_widget.dart';

@immutable
class TiledEditorTab extends EditorTab {
  @override
  final GlobalKey<TiledEditorWidgetState> editorKey;

  // The raw TMX content loaded by the FileContentProvider.
  final String initialTmxContent;
  // The hash of the content when it was loaded from disk.
  final String initialBaseContentHash;

  TiledEditorTab({
    required super.plugin,
    required this.initialTmxContent,
    required this.initialBaseContentHash,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<TiledEditorWidgetState>();

  @override
  void dispose() {
    // Nothing to dispose here, the widget state handles it.
  }
}
