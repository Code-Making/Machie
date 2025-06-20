// lib/explorer/plugins/search_explorer/search_explorer_state.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../project/project_models.dart';
import '../../../data/repositories/project_repository.dart'; // REFACTOR
import '../../../app/app_notifier.dart'; // REFACTOR

// ... (SearchState model is unchanged) ...
class SearchState {
  final String query;
  final List<DocumentFile> results;
  final bool isLoading;

  SearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
  });

  SearchState copyWith({
    String? query,
    List<DocumentFile>? results,
    bool? isLoading,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// REFACTOR: The family parameter is now just the project ID for simplicity.
final searchStateProvider = StateNotifierProvider.autoDispose
    .family<SearchStateNotifier, SearchState, String>((ref, projectId) {
  final repo = ref.watch(projectRepositoryProvider);
  if (repo == null) {
    // Return a dummy notifier if the repository isn't ready.
    return SearchStateNotifier(null, '');
  }
  final project = ref.watch(appNotifierProvider).value?.currentProject;
  return SearchStateNotifier(repo, project?.rootUri ?? '');
});

class SearchStateNotifier extends StateNotifier<SearchState> {
  // REFACTOR: Now depends on the repository, not a direct FileHandler.
  final ProjectRepository? _repo;
  final String _rootUri;
  List<DocumentFile>? _allFilesCache;
  Timer? _debounce;

  SearchStateNotifier(this._repo, this._rootUri) : super(SearchState());

  Future<void> _fetchAllFiles() async {
    if (_repo == null) return;
    state = state.copyWith(isLoading: true);
    final allFiles = <DocumentFile>[];
    final directoriesToScan = <String>[_rootUri];

    while (directoriesToScan.isNotEmpty) {
      final currentDirUri = directoriesToScan.removeAt(0);
      try {
        final items = await _repo!.listDirectory(currentDirUri);
        for (final item in items) {
          if (item.isDirectory) {
            directoriesToScan.add(item.uri);
          } else {
            allFiles.add(item);
          }
        }
      } catch (e) {
        // Log error but continue scanning other directories.
        // talker.error('Error scanning directory $currentDirUri: $e');
      }
    }
    _allFilesCache = allFiles;
    state = state.copyWith(isLoading: false);
  }

  void search(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (_repo == null) return;
      state = state.copyWith(query: query);
      if (query.isEmpty) {
        state = state.copyWith(results: []);
        return;
      }

      if (_allFilesCache == null) {
        await _fetchAllFiles();
      }

      if (_allFilesCache == null) return;

      final lowerCaseQuery = query.toLowerCase();
      final results = _allFilesCache!
          .where((file) => file.name.toLowerCase().contains(lowerCaseQuery))
          .toList();

      if (mounted) {
        state = state.copyWith(results: results);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}