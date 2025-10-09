// =========================================
// NEW FILE: lib/editor/plugins/git_diff/git_diff_plugin.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/git_diff/git_diff_models.dart';
import 'package:machine/editor/plugins/git_diff/git_diff_widget.dart';

import '../../../command/command_models.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../editor_tab_models.dart';
import '../plugin_models.dart';

class GitDiffPlugin extends EditorPlugin {
  @override
  String get id => 'com.machine.git_diff_viewer';

  @override
  String get name => 'Git Diff Viewer';

  @override
  Widget get icon => const Icon(Icons.difference_outlined);

  // Give it a higher priority than the default CodeEditor (priority 0)
  // so it gets the first chance to claim the file content.
  @override
  int get priority => 5;

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  // This plugin can technically open any file, but the real check is in canOpenFileContent.
  @override
  bool supportsFile(DocumentFile file) => true;

  /// This is the key detection logic. A file is considered a diff if it contains
  /// hunk headers, which is a strong indicator.
  @override
  bool canOpenFileContent(String content, DocumentFile file) {
    // A simple but effective heuristic: check for standard diff hunk syntax.
    return content.contains('\n@@ ') || content.startsWith('@@ ');
  }

  // --- TAB AND EDITOR CREATION ---

  @override
  Future<EditorTab> createTab(DocumentFile file, EditorInitData initData, {String? id}) async {
    return GitDiffTab(
      plugin: this,
      diffContent: initData.stringData ?? '',
      id: id,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    final diffTab = tab as GitDiffTab;
    return GitDiffEditorWidget(
      key: diffTab.editorKey,
      tab: diffTab,
    );
  }

  // --- STATELESS & READ-ONLY IMPLEMENTATIONS ---

  // This is a read-only viewer, so it has no commands, settings, or caching.
  @override
  List<Command> getCommands() => [];
  
  @override
  PluginSettings? get settings => null;

  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => null;

  @override
  String? get hotStateDtoType => null;

  @override
  Type? get hotStateDtoRuntimeType => null;
}