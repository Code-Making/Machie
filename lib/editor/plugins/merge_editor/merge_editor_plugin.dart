import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Added for WidgetRef
import 'package:machine/data/dto/tab_hot_state_dto.dart'; // Added for TabHotStateDto
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/merge_editor/merge_editor_models.dart';
import 'package:machine/editor/plugins/merge_editor/merge_editor_widget.dart';
import 'package:machine/editor/plugins/plugin_models.dart';
import 'package:machine/data/file_handler/file_handler.dart';

class MergeEditorPlugin extends EditorPlugin {
  @override
  String get id => 'com.machine.merge_editor';

  @override
  String get name => 'Merge Conflict Editor';

  @override
  Widget get icon => const Icon(Icons.merge_type);

  // Give it a high priority to ensure it checks files before the default code editor.
  @override
  int get priority => 10;
  
  // This plugin uses string data.
  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  // The key check: does the file content have conflict markers?
  @override
  bool canOpenFileContent(String content, DocumentFile file) {
    return content.contains('<<<<<<<');
  }

  // It supports any file, as the content is the deciding factor.
  @override
  bool supportsFile(DocumentFile file) => true;

  @override
  Future<EditorTab> createTab(DocumentFile file, EditorInitData initData, {String? id}) async {
    return MergeEditorTab(
      plugin: this,
      initialContent: initData.stringData ?? '',
      id: id,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return MergeEditorWidget(
      key: (tab as MergeEditorTab).editorKey,
      tab: tab,
    );
  }

  // This plugin is transient and doesn't support caching.
  @override
  String? get hotStateDtoType => null;
  @override
  Type? get hotStateDtoRuntimeType => null;
  @override
  get hotStateAdapter => null;
}