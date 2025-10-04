// =========================================
// FINAL, SIMPLIFIED FILE: lib/project/services/project_file_cache.dart
// =========================================
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:machine/project/project_models.dart';

// The state is now simpler. No more isFullyScanned or scanState.
class ProjectFileCacheState {
  final Map<String, List<DocumentFile>> directoryContents;
  final Set<String> loadingDirectories;

  const ProjectFileCacheState({
    this.directoryContents = const {},
    this.loadingDirectories = const {},
  });

  ProjectFileCacheState copyWith({
    Map<String, List<DocumentFile>>? directoryContents,
    Set<String>? loadingDirectories,
  }) {
    return ProjectFileCacheState(
      directoryContents: directoryContents ?? this.directoryContents,
      loadingDirectories: loadingDirectories ?? this.loadingDirectories,
    );
  }
}

final projectFileCacheProvider =
    NotifierProvider<ProjectFileCacheNotifier, ProjectFileCacheState>(
        ProjectFileCacheNotifier.new);

class ProjectFileCacheNotifier extends Notifier<ProjectFileCacheState> {
  @override
  ProjectFileCacheState build() {
    ref.listen<Project?>(
      appNotifierProvider.select((s) => s.value?.currentProject),
      (previous, next) {
        if (next == null) {
          state = const ProjectFileCacheState();
        }
      },
    );
    return const ProjectFileCacheState();
  }

  /// The SINGLE method for loading directory contents.
  /// It now returns the list of files it loaded.
  Future<List<DocumentFile>> loadDirectory(String uri) async {
    // If we are already loading it, return an empty list to avoid duplicates.
    if (state.loadingDirectories.contains(uri)) {
      return [];
    }
    // If it's already cached, return the cached content.
    if (state.directoryContents.containsKey(uri)) {
      return state.directoryContents[uri]!;
    }

    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return [];

    ref.read(talkerProvider).info('Loading directory: $uri');
    state = state.copyWith(loadingDirectories: {...state.loadingDirectories, uri});

    try {
      final contents = await repo.listDirectory(uri);
      state = state.copyWith(
        directoryContents: {...state.directoryContents, uri: contents},
        loadingDirectories: {...state.loadingDirectories}..remove(uri),
      );
      return contents;
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Failed to load directory: $uri');
      state = state.copyWith(
        loadingDirectories: {...state.loadingDirectories}..remove(uri),
      );
      // Re-throw the error so the caller (like ensureFullCacheIsBuilt) knows it failed.
      rethrow;
    }
  }

  /// Orchestrates the full, recursive scan by repeatedly calling `loadDirectory`.
  /// Returns a Future that completes when the entire scan is finished.
  Future<void> ensureFullCacheIsBuilt() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null) return;

    // Use a Set to keep track of directories we need to visit.
    final directoriesToScan = <String>{project.rootUri};
    // Use a Set to prevent re-scanning directories we've already processed.
    final scannedUris = <String>{};

    // Keep scanning as long as there are new directories to process.
    while (directoriesToScan.isNotEmpty) {
      // Create a list of futures for the current batch of directories to scan.
      final futures = directoriesToScan.map((uri) async {
        scannedUris.add(uri);
        return loadDirectory(uri);
      }).toList();

      // Clear the set for the next iteration.
      directoriesToScan.clear();

      // Wait for all directories in the current level to finish loading.
      final results = await Future.wait(futures);

      // Go through the results and add any new subdirectories to the set for the next loop.
      for (final files in results) {
        for (final file in files) {
          if (file.isDirectory && !scannedUris.contains(file.uri)) {
            directoriesToScan.add(file.uri);
          }
        }
      }
    }
    ref.read(talkerProvider).info('[ProjectFileCache] Full scan validation complete.');
  }
}