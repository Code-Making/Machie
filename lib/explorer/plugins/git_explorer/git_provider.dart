import 'package:dart_git/dart_git.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/project/project_repository.dart';
import '../../../logs/logs_provider.dart';
import 'git_storage_provider.dart';

/// A provider that attempts to load a dart_git GitRepository for the current project.
///
/// It's a `FutureProvider` because initializing the repository is now an asynchronous
/// operation involving filesystem checks. It returns `null` if the current project
/// is not a valid Git repository.
final gitRepositoryProvider = FutureProvider<GitRepository?>((ref) async {
  final projectRepo = ref.watch(projectRepositoryProvider);
  if (projectRepo == null) {
    return null;
  }

  final fileHandler = projectRepo.fileHandler;
  final rootUri = projectRepo.rootUri;
  final talker = ref.read(talkerProvider);

  final provider = AppStorageProvider(fileHandler);

  final workTreeFile = await fileHandler.getFileMetadata(rootUri);
  if (workTreeFile == null) return null;
  final workTreeHandle = AppStorageHandle(workTreeFile);

  final gitDirHandle = await provider.resolve(workTreeHandle, '.git');

  final headHandle = await provider.resolve(gitDirHandle, 'HEAD');
  if (!await provider.exists(headHandle)) {
    talker.info("Project at $rootUri is not a Git repository.");
    return null;
  }

  try {
    final repo = await GitRepository.fromProviders(
      workTreeProvider: provider,
      gitDirProvider: provider,
      workTree: workTreeHandle,
      gitDir: gitDirHandle,
    );

    ref.onDispose(() {
      repo.objStorage.close();
      repo.refStorage.close();
      repo.indexStorage.close();
    });
    await repo.reloadConfig();

    return repo;
  } catch (e, st) {
    talker.handle(
      e,
      st,
      "Failed to load Git repository from providers at $rootUri",
    );
    return null;
  }
});
