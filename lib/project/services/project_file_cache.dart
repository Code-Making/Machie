// =========================================
// NEW FILE: lib/project/services/project_file_cache.dart
// =========================================
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/logs/logs_provider.dart';

// The state that our new provider will manage.
class ProjectFileCacheState {
  // For the hierarchical view (File Explorer). Key is directory URI.
  final Map<String, List<DocumentFile>> directoryContents;

  // To prevent multiple concurrent loads of the same directory.
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

// The new unified provider. It replaces `projectHierarchyProvider`.
final projectFileCacheProvider =
    StateNotifierProvider<ProjectFileCacheNotifier, ProjectFileCacheState>(
        (ref) {
  return ProjectFileCacheNotifier(ref);
});

class ProjectFileCacheNotifier extends StateNotifier<ProjectFileCacheState> {
  final Ref _ref;

  ProjectFileCacheNotifier(this._ref) : super(const ProjectFileCacheState()) {
    // Sync the cache's lifecycle with the current project.
    _ref.listen<Project?>(
      appNotifierProvider.select((s) => s.value?.currentProject),
      (previous, next) {
        if (next == null) {
          // If project is closed, clear the cache.
          state = const ProjectFileCacheState();
        }
      },
    );
  }

  /// Lazily loads the contents of a single directory if not already cached.
  Future<void> loadDirectory(String uri) async {
    // Prevent re-fetching if we already have it or are currently loading it.
    if (state.directoryContents.containsKey(uri) || state.loadingDirectories.contains(uri)) {
      return;
    }

    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) return;

    _ref.read(talkerProvider).info('Lazy loading directory: $uri');
    state = state.copyWith(loadingDirectories: {...state.loadingDirectories, uri});

    try {
      final contents = await repo.listDirectory(uri);
      if (mounted) {
        state = state.copyWith(
          directoryContents: {...state.directoryContents, uri: contents},
          loadingDirectories: {...state.loadingDirectories}..remove(uri),
        );
      }
    } catch (e, st) {
      _ref.read(talkerProvider).handle(e, st, 'Failed to load directory: $uri');
      if (mounted) {
        state = state.copyWith(
          loadingDirectories: {...state.loadingDirectories}..remove(uri),
        );
      }
    }
  }
}