// lib/explorer/plugins/search_explorer/search_explorer_plugin.dart

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/content_provider/file_content_provider.dart';
import '../../../project/project_models.dart';
import '../../explorer_plugin_models.dart';
import 'search_explorer_settings_widget.dart';
import 'search_explorer_view.dart';
import 'search_explorer_settings.dart';

class SearchExplorerPlugin implements ExplorerPlugin {
  @override
  String get id => 'com.machine.search_explorer';

  @override
  String get name => 'Search';

  @override
  IconData get icon => Icons.search;

  @override
  final ExplorerPluginSettings? settings = SearchExplorerSettings();

  @override
  Widget buildSettingsUI(
    ExplorerPluginSettings settings,
    void Function(ExplorerPluginSettings) onChanged,
  ) {
    return SearchExplorerSettingsUI(
      settings: settings as SearchExplorerSettings,
      onChanged: onChanged,
    );
  }


  @override
  List<FileContentProvider Function(Ref ref)>
  get fileContentProviderFactories => [];

  @override
  Widget build(WidgetRef ref, Project project) {
    return SearchExplorerView(project: project);
  }
}
