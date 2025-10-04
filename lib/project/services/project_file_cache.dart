// = a=======================================
// FINAL CORRECTED FILE: lib/project/services/project_file_cache.dart
// =========================================
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:machine/project/project_models.dart';

// The state class remains the same.
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

// CORRECTED: The provider is now a NotifierProvider.
final projectFileCacheProvider =
    NotifierProvider<ProjectFileCacheNotifier, ProjectFileCacheState>(
        ProjectFileCacheNotifier.new);

// CORRECTED: The class now extends Notifier.
class ProjectFileCacheNotifier extends Notifier<ProjectFileCacheState> {

  // The build method is called once when the provider is first read.
  // This is the perfect place to set up the initial state and listeners.
  @override
  ProjectFileCacheState build() {
    // Sync the cache's lifecycle with the current project.
    ref.listen<Project?>(
      appNotifierProvider.select((s) => s.value?.currentProject),
      (previous, next) {
        if (next == null) {
          // If project is closed, reset the cache to its initial state.
          state = const ProjectFileCacheState();
        }
      },
    );

    // Return the initial state.
    return const ProjectFileCacheState();
  }

  /// Lazily loads the contents of a single directory if not already cached.
  Future<void> loadDirectory(String uri) async {
    // `ref` is now a property of the Notifier class, so we can use it directly.
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) {
      ref.read(talkerProvider).warning('Attempted to load directory but no project repository is active.');
      return;
    }

    if (state.directoryContents.containsKey(uri) || state.loadingDirectories.contains(uri)) {
      return;
    }

    ref.read(talkerProvider).info('Lazy loading directory: $uri');
    state = state.copyWith(loadingDirectories: {...state.loadingDirectories, uri});

    try {
      final contents = await repo.listDirectory(uri);
      // Riverpod ensures `mounted` is implicitly handled for Notifiers.
      state = state.copyWith(
        directoryContents: {...state.directoryContents, uri: contents},
        loadingDirectories: {...state.loadingDirectories}..remove(uri),
      );
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Failed to load directory: $uri');
      state = state.copyWith(
        loadingDirectories: {...state.loadingDirectories}..remove(uri),
      );
    }
  }

  // The clear method is no longer needed, as the `ref.listen` in `build`
  // handles the reset automatically when the project closes.
}