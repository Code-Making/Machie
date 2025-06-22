// lib/explorer/plugins/search_explorer/search_explorer_state.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/project_hierarchy_cache.dart';
import '../../../app/app_notifier.dart';
import '../../../logs/logs_provider.dart';

// ... SearchState model is unchanged ...
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

final searchStateProvider = StateNotifierProvider.autoDispose
    .family<SearchStateNotifier, SearchState, String>((ref, projectId) {
  final hierarchyCache = ref.watch(projectHierarchyProvider);
  final project = ref.watch(appNotifierProvider).value?.currentProject;
  final talker = ref.read(talkerProvider);

  // REFACTOR: Pass the ref to the notifier so it can listen to changes.
  return SearchStateNotifier(
    hierarchyCache,
    project?.rootUri ?? '',
    talker,
    ref,
  );
});

class SearchStateNotifier extends StateNotifier<SearchState> {
  final ProjectHierarchyCache? _hierarchyCache;
  final String _rootUri;
  final Talker _talker;
  List<DocumentFile>? _allFilesCache;
  Timer? _debounce;

  // REFACTOR: Accept Ref to enable listening.
  SearchStateNotifier(
    this._hierarchyCache,
    this._rootUri,
    this._talker,
    Ref ref,
  ) : super(SearchState()) {
    // REFACTOR: This is the core of the fix.
    // Listen to changes in the central hierarchy cache.
    // If the cache changes due to a file operation elsewhere,
    // we invalidate our local search cache.
    ref.listen(projectHierarchyProvider, (previous, next) {
      // We only care that it changed, not what the change was.
      if (previous != next) {
        _talker.info('Search cache detected a change in the hierarchy. Invalidating local cache.');
        _allFilesCache = null;

        // If a search is active, re-run it to show fresh results.
        if (state.query.isNotEmpty) {
          search(state.query);
        }
      }
    });
  }

  // ... _fetchAllFiles is unchanged ...
  Future<void> _fetchAllFiles() async {
    if (_hierarchyCache == null || _rootUri.isEmpty) return;
    if (!mounted) return;
    state = state.copyWith(isLoading: true);

    final allFiles = <DocumentFile>[];
    final directoriesToScan = <String>[_rootUri];
    final scannedUris = <String>{};

    while (directoriesToScan.isNotEmpty) {
      final currentDirUri = directoriesToScan.removeAt(0);
      if (scannedUris.contains(currentDirUri)) continue;
      scannedUris.add(currentDirUri);

      try {
        await _hierarchyCache!.loadDirectory(currentDirUri);
        final items = _hierarchyCache!.state[currentDirUri];
        if (items == null) continue;

        for (final item in items) {
          if (item.isDirectory) {
            directoriesToScan.add(item.uri);
          } else {
            allFiles.add(item);
          }
        }
      } catch (e, st) {
        _talker.handle(e, st, 'Error scanning directory $currentDirUri during search');
      }
    }
    _allFilesCache = allFiles;
    if (mounted) {
      state = state.copyWith(isLoading: false);
    }
  }
  
  void search(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (_hierarchyCache == null) return;
      if (!mounted) return;
      state = state.copyWith(query: query);
      if (query.isEmpty) {
        state = state.copyWith(results: []);
        return;
      }

      if (_allFilesCache == null) {
        await _fetchAllFiles();
      }

      if (_allFilesCache == null || !mounted) return;

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