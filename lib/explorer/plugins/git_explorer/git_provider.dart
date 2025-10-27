// lib/explorer/plugins/git_explorer/git_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/git.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/logs/logs_provider.dart';

/// A provider that attempts to load a dart_git GitRepository for the current project.
/// Returns null if the current project is not a git repository.
final gitRepositoryProvider = Provider<GitRepository?>((ref) {
  final project = ref.watch(appNotifierProvider).value?.currentProject;
  if (project == null) {
    return null;
  }

  // GitRepository.findRootDir might be better, but we already have the root.
  // We just need to check if it's a valid repo.
  if (GitRepository.isValidRepo(project.rootUri)) {
    try {
      final repo = GitRepository.load(project.rootUri);
      ref.onDispose(() => repo.close());
      return repo;
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, "Failed to load Git repository at ${project.rootUri}");
      return null;
    }
  }

  return null;
});