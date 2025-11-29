// lib/explorer/plugins/file_explorer/file_explorer_plugin.dart

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/content_provider/file_content_provider.dart';
import '../../../project/project_models.dart';
import '../../explorer_plugin_models.dart';
import 'file_explorer_view.dart';

import 'file_explorer_state.dart'; // REFACTOR: Keep for the settings model

class FileExplorerPlugin implements ExplorerPlugin {
  @override
  String get id => 'com.machine.file_explorer';

  @override
  String get name => 'File Explorer';

  @override
  IconData get icon => Icons.folder_open;

  @override
  final ExplorerPluginSettings? settings = FileExplorerSettings();

  @override
  Widget buildSettingsUI(
    ExplorerPluginSettings settings,
    void Function(ExplorerPluginSettings) onChanged,
  ) => const SizedBox.shrink();

  @override
  List<FileContentProvider Function(Ref ref)>
  get fileContentProviderFactories => [];

  @override
  Widget build(WidgetRef ref, Project project) {
    return FileExplorerView(project: project);
  }
}
