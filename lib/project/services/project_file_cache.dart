// =========================================
// CORRECTED FILE: lib/project/services/project_file_cache.dart
// =========================================
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:machine/project/project_models.dart'; // CORRECTED IMPORT

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

// CORRECTED: The provider now correctly constructs the notifier with its dependencies.
// It is now an autoDispose provider, which is good practice. Its lifecycle
// will be managed by what's listening to it.
final projectFileCacheProvider = StateNotifierProvider.autoDispose<
    ProjectFileCacheNotifier, ProjectFileCacheState>((ref) {
  final talker = ref.watch(talkerProvider);
  // The cache depends on the currently active project repository.
  final repo = ref.watch(projectRepositoryProvider);

  // If no project is open, the repo is null. We pass null to the notifier.
  final notifier = ProjectFileCacheNotifier(talker, repo);

  // When the provider is disposed (e.g., when the last listener is removed),
  // we can perform cleanup if needed.
  ref.onDispose(() {
    // notifier.dispose(); // if you had any streams/timers to cancel
  });

  return notifier;
});

class ProjectFileCacheNotifier extends StateNotifier<ProjectFileCacheState> {
  // CORRECTED: Dependencies are now constructor-injected, not via a ref property.
  final Talker _talker;
  final ProjectRepository? _repo;

  ProjectFileCacheNotifier(this._talker, this._repo)
      : super(const ProjectFileCacheState());

  /// Lazily loads the contents of a single directory if not already cached.
  Future<void> loadDirectory(String uri) async {
    // CORRECTED: Check for null repository.
    final repo = _repo;
    if (repo == null) {
      _talker.warning('Attempted to load directory but no project repository is active.');
      return;
    }

    if (state.directoryContents.containsKey(uri) || state.loadingDirectories.contains(uri)) {
      return;
    }

    _talker.info('Lazy loading directory: $uri');
    state = state.copyWith(loadingDirectories: {...state.loadingDirectories, uri});

    try {
      // CORRECTED: Use the injected repository to perform the file operation.
      final contents = await repo.listDirectory(uri);
      if (mounted) {
        state = state.copyWith(
          directoryContents: {...state.directoryContents, uri: contents},
          loadingDirectories: {...state.loadingDirectories}..remove(uri),
        );
      }
    } catch (e, st) {
      _talker.handle(e, st, 'Failed to load directory: $uri');
      if (mounted) {
        state = state.copyWith(
          loadingDirectories: {...state.loadingDirectories}..remove(uri),
        );
      }
    }
  }

  // ADDED: A clear method for when a project is closed.
  void clear() {
    state = const ProjectFileCacheState();
  }
}