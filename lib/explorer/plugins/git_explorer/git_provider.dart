import 'package:dart_git/dart_git.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../../logs/logs_provider.dart';
import 'git_storage_provider.dart';

/// A provider that attempts to load a dart_git GitRepository for the current project.
///
/// It's a `FutureProvider` because initializing the repository is now an asynchronous
/// operation involving filesystem checks. It returns `null` if the current project
/// is not a valid Git repository.
final gitRepositoryProvider = FutureProvider<GitRepository?>((ref) async {
  final project = ref.watch(appNotifierProvider).value?.currentProject;
  final projectRepo = ref.watch(projectRepositoryProvider);

  // If there's no open project, there's no repository to load.
  if (project == null || projectRepo == null) {
    return null;
  }

  // 1. Instantiate our custom AppStorageProvider, bridging dart_git to our app's FileHandler.
  final provider = AppStorageProvider(projectRepo.fileHandler);

  // 2. Create the root handle for the project's working tree.
  final workTreeFile = await projectRepo.fileHandler.getFileMetadata(
    project.rootUri,
  );
  if (workTreeFile == null) return null;
  final workTreeHandle = AppStorageHandle(workTreeFile);

  // 3. Resolve the .git directory handle relative to the working tree.
  final gitDirHandle = await provider.resolve(workTreeHandle, '.git');

  // 4. Check if it's a valid repo by looking for a critical file like HEAD.
  //    This is more reliable than just checking for the .git directory's existence.
  final headHandle = await provider.resolve(gitDirHandle, 'HEAD');
  if (!await provider.exists(headHandle)) {
    ref
        .read(talkerProvider)
        .info("Project at ${project.rootUri} is not a Git repository.");
    return null;
  }

  // 5. Create the GitRepository instance using the new asynchronous, provider-based factory.
  try {
    final repo = await GitRepository.fromProviders(
      workTreeProvider: provider,
      gitDirProvider: provider, // For non-bare repos, these are the same.
      workTree: workTreeHandle,
      gitDir: gitDirHandle,
    );

    // Ensure resources are cleaned up if the provider is disposed.
    ref.onDispose(() {
      repo.objStorage.close();
      repo.refStorage.close();
      repo.indexStorage.close();
    });
    // Load the repository's configuration.
    await repo.reloadConfig();

    return repo;
  } catch (e, st) {
    ref
        .read(talkerProvider)
        .handle(
          e,
          st,
          "Failed to load Git repository from providers at ${project.rootUri}",
        );
    return null;
  }
});
