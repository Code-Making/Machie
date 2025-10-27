// lib/explorer/plugins/git_explorer/git_explorer_plugin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/services/file_content_provider.dart';
import 'package:machine/explorer/explorer_plugin_models.dart';
import 'package:machine/project/project_models.dart';
import 'git_file_content_provider.dart';
import 'git_explorer_view.dart';
import 'git_provider.dart'; // IMPORT THE GIT PROVIDER

class GitExplorerPlugin implements ExplorerPlugin {
  @override
  String get id => 'com.machine.git_explorer';

  @override
  String get name => 'Git History';

  @override
  IconData get icon => Icons.history;

  @override
  ExplorerPluginSettings? get settings => null;

  // UPDATED: Provide a factory function instead of an instance.
  @override
  List<FileContentProvider Function(Ref ref)> get fileContentProviderFactories => [
        // This factory will be called by the central registry.
        // It reads the gitRepositoryProvider and injects the GitRepository object.
        (ref) {
          final gitRepo = ref.watch(gitRepositoryProvider);
          // This factory must return a valid provider. We throw if the dependency is missing.
          // The registry will handle this gracefully.
          if (gitRepo == null) {
            throw StateError('GitRepository not available for GitFileContentProvider');
          }
          return GitFileContentProvider(gitRepo);
        }
      ];

  @override
  Widget build(WidgetRef ref, Project project) {
    return GitExplorerView(project: project);
  }
}