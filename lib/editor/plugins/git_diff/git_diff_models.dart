// =========================================
// NEW FILE: lib/editor/plugins/git_diff/git_diff_models.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/git_diff/git_diff_widget.dart';
import '../../editor_tab_models.dart';
import '../plugin_models.dart';

@immutable
class GitDiffTab extends EditorTab {
  @override
  final GlobalKey<GitDiffEditorWidgetState> editorKey;
  
  final String diffContent;

  GitDiffTab({
    required super.plugin,
    required this.diffContent,
    super.id,
  }) : editorKey = GlobalKey<GitDiffEditorWidgetState>();

  @override
  void dispose() {}
}