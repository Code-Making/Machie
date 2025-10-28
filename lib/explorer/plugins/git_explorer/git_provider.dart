// lib/explorer/plugins/git_explorer/git_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_name/dart_git.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/logs/logs_provider.dart';
import 'git_storage_provider.dart';

/// A provider that attempts to load a dart_git GitRepository for the current project
/// using the new provider-based architecture.
final gitRepositoryProvider = FutureProvider<GitRepository?>((ref) async {
  final project = ref.watch(appNotifierProvider).value?.currentProject;
  final projectRepo = ref.watch(projectRepositoryProvider);

  if (project == null || projectRepo == null) {
    return null;
  }

  // 1. Instantiate our custom provider with the app's file handler.
  final provider = AppStorageProvider(projectRepo.fileHandler);
  
  // 2. Create the root handle for the project's working tree.
  final workTreeFile = await projectRepo.fileHandler.getFileMetadata(project.rootUri);
  if (workTreeFile == null) return null;
  final workTreeHandle = AppStorageHandle(workTreeFile);
  
  // 3. Resolve the .git directory handle.
  final gitDirHandle = await provider.resolve(workTreeHandle, '.git');
  
  // 4. Check if it's a valid repo by looking for the HEAD file.
  final headHandle = await provider.resolve(gitDirHandle, 'HEAD');
  if (!await provider.exists(headHandle)) {
    ref.read(talkerProvider).info("Project at ${project.rootUri} is not a Git repository.");
    return null;
  }

  // 5. Create the GitRepository instance using the async factory.
  try {
    final repo = await GitRepository.fromProviders(
      workTreeProvider: provider,
      gitDirProvider: provider, // Using the same provider for both
      workTree: workTreeHandle,
      gitDir: gitDirHandle,
    );
    ref.onDispose(() => repo.close());
    await repo.reloadConfig();
    return repo;
  } catch (e, st) {
    ref.read(talkerProvider).handle(e, st, "Failed to load Git repository from providers at ${project.rootUri}");
    return null;
  }
});