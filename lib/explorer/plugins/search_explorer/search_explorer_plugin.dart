// lib/explorer/plugins/search_explorer/search_explorer_plugin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project/project_models.dart';
import '../../explorer_plugin_models.dart';
import 'search_explorer_view.dart';

/// The concrete implementation of the ExplorerPlugin for searching files.
class SearchExplorerPlugin implements ExplorerPlugin {
  @override
  String get id => 'com.machine.search_explorer';

  @override
  String get name => 'Search';

  @override
  IconData get icon => Icons.search;

  @override
  Widget build(WidgetRef ref, Project project) {
    // The plugin's build method simply returns the dedicated view widget.
    return SearchExplorerView(project: project);
  }
}
