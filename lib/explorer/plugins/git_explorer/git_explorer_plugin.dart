// lib/explorer/plugins/git_explorer/git_explorer_plugin.dart

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../editor/services/file_content_provider.dart';
import '../../../project/project_models.dart';
import '../../explorer_plugin_models.dart';
import 'git_explorer_view.dart';
import 'git_file_content_provider.dart';

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
  List<FileContentProvider Function(Ref ref)>
  get fileContentProviderFactories => [
    // This factory will be called by the central registry.
    (ref) {
      // It watches the async provider for the GitRepository.
      final gitRepoAsyncValue = ref.watch(gitRepositoryProvider);

      // It must return a valid provider. We throw if the dependency is not
      // yet available or has failed to load. The registry is designed to
      // handle this gracefully by simply not registering this provider.
      final repo = gitRepoAsyncValue.valueOrNull;
      if (repo == null) {
        throw StateError(
          'GitRepository not available for GitFileContentProvider',
        );
      }

      // Once the dependency is ready, we instantiate our plain Dart class.
      return GitFileContentProvider(repo);
    },
  ];

  @override
  Widget build(WidgetRef ref, Project project) {
    return GitExplorerView(project: project);
  }
}
