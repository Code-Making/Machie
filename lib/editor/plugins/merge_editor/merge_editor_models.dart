import 'package:flutter/material.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/merge_editor/merge_editor_widget.dart';

@immutable
class MergeEditorTab extends EditorTab {
  @override
  final GlobalKey<MergeEditorWidgetState> editorKey;

  final String initialContent;
  // This editor doesn't need caching/hashing as it's for a transient state
  // but we could add it if we wanted to preserve resolved chunks.

  MergeEditorTab({
    required super.plugin,
    required this.initialContent,
    super.id,
  }) : editorKey = GlobalKey<MergeEditorWidgetState>();

  @override
  void dispose() {}
}