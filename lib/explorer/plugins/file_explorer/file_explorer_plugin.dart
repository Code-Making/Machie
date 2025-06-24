// lib/explorer/plugins/file_explorer/file_explorer_plugin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project/project_models.dart';
import '../../explorer_plugin_models.dart';
import 'file_explorer_state.dart'; // REFACTOR: Keep for the settings model
import 'file_explorer_view.dart';

class FileExplorerPlugin implements ExplorerPlugin {
  @override
  String get id => 'com.machine.file_explorer';

  @override
  String get name => 'File Explorer';

  @override
  IconData get icon => Icons.folder_open;

  // REFACTOR: The plugin now provides its settings object.
  @override
  final ExplorerPluginSettings? settings = FileExplorerSettings();

  @override
  Widget build(WidgetRef ref, Project project) {
    return FileExplorerView(project: project);
  }
}
