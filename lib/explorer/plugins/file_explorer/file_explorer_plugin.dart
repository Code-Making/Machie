// lib/explorer/plugins/file_explorer/file_explorer_plugin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project/project_models.dart';
import '../../explorer_plugin_models.dart';
import 'file_explorer_view.dart';

/// The concrete implementation of the ExplorerPlugin for browsing the file system.
class FileExplorerPlugin implements ExplorerPlugin {
  @override
  String get id => 'com.machine.file_explorer';

  @override
  String get name => 'File Explorer';

  @override
  IconData get icon => Icons.folder_open;

  @override
  Widget build(WidgetRef ref, Project project) {
    // The plugin's build method simply returns the dedicated view widget.
    // It passes the project along so the view knows what to render.
    return FileExplorerView(project: project);
  }
}