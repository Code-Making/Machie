// lib/explorer/plugins/search_explorer/search_explorer_plugin.dart

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../editor/services/file_content_provider.dart';
import '../../../project/project_models.dart';
import '../../explorer_plugin_models.dart';
import 'search_explorer_view.dart';

class SearchExplorerPlugin implements ExplorerPlugin {
  @override
  String get id => 'com.machine.search_explorer';

  @override
  String get name => 'Search';

  @override
  IconData get icon => Icons.search;

  // REFACTOR: Stateless plugins simply return null for settings.
  @override
  ExplorerPluginSettings? get settings => null;

  @override
  List<FileContentProvider Function(Ref ref)>
  get fileContentProviderFactories => [];

  @override
  Widget build(WidgetRef ref, Project project) {
    return SearchExplorerView(project: project);
  }
}
