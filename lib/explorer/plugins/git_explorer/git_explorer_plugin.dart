import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/content_provider/file_content_provider.dart';
import '../../../project/project_models.dart';
import '../../explorer_plugin_models.dart';
import 'git_explorer_view.dart';
import 'git_file_content_provider.dart';

import 'git_provider.dart';

class GitExplorerPlugin implements ExplorerPlugin {
  @override
  String get id => 'com.machine.git_explorer';

  @override
  String get name => 'Git History';

  @override
  IconData get icon => Icons.history;

  @override
  ExplorerPluginSettings? get settings => null;

  @override
  Widget buildSettingsUI(
    ExplorerPluginSettings settings,
    void Function(ExplorerPluginSettings) onChanged,
  ) =>
      const SizedBox.shrink();

  @override
  List<FileContentProvider Function(Ref ref)>
  get fileContentProviderFactories => [
    (ref) {
      final gitRepoFuture = ref.read(gitRepositoryProvider.future);
      return GitFileContentProvider(gitRepoFuture);
    },
  ];

  @override
  Widget build(WidgetRef ref, Project project) {
    return GitExplorerView(project: project);
  }
}
