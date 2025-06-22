// lib/explorer/plugins/search_explorer/search_explorer_state.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/project_hierarchy_cache.dart'; // NEW IMPORT
import '../../../app/app_notifier.dart';
import '../../../logs/logs_provider.dart'; // NEW IMPORT

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

// REFACTOR: Provider now depends on the hierarchy cache.
final searchStateProvider = StateNotifierProvider.autoDispose
    .family<SearchStateNotifier, SearchState, String>((ref, projectId) {
  final hierarchyCache = ref.watch(projectHierarchyProvider);
  final project = ref.watch(appNotifierProvider).value?.currentProject;
  final talker = ref.read(talkerProvider);

  return SearchStateNotifier(
    hierarchyCache,
    project?.rootUri ?? '',
    talker,
  );
});

class SearchStateNotifier extends StateNotifier<SearchState> {
  // REFACTOR: Depend on the cache, not the whole repository.
  final ProjectHierarchyCache? _hierarchyCache;
  final String _rootUri;
  final Talker _talker;
  List<DocumentFile>? _allFilesCache;
  Timer? _debounce;

  SearchStateNotifier(this._hierarchyCache, this._rootUri, this._talker)
      : super(SearchState());

  // REFACTOR: This method now uses and populates the central cache.
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
        // Ensure the directory is loaded in the central cache. This will
        // fetch it from the file system if it's not already there.
        await _hierarchyCache!.loadDirectory(currentDirUri);

        // Get the now-cached contents.
        final items = _hierarchyCache!.state[currentDirUri];
        if (items == null) continue; // Should not happen, but a safe check.

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