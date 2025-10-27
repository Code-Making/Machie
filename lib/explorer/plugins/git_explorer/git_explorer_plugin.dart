// lib/explorer/plugins/git_explorer/git_explorer_plugin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/services/file_content_provider.dart';
import 'package:machine/explorer/explorer_plugin_models.dart';
import 'package:machine/project/project_models.dart';
import 'git_file_content_provider.dart';
import 'git_explorer_view.dart';

class GitExplorerPlugin implements ExplorerPlugin {
  @override
  String get id => 'com.machine.git_explorer';

  @override
  String get name => 'Git History';

  @override
  IconData get icon => Icons.history;

  @override
  ExplorerPluginSettings? get settings => null; // This plugin is stateless

  @override
  List<FileContentProvider> get fileContentProviders => [
        // This is the crucial part that registers our custom provider
        GitFileContentProvider(
            // We need a ref here. This is a bit of a workaround.
            // A better solution would be dependency injection into the provider constructor.
            ProviderScope.containerOf(
                // A bit of a hack to get a context, should ideally be passed in.
                // Assuming a global key or similar is available if needed.
                GlobalKey().currentContext!,
                listen: false)),
      ];

  @override
  Widget build(WidgetRef ref, Project project) {
    return GitExplorerView(project: project);
  }
}