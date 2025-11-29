// FILE: lib/explorer/plugins/search_explorer/search_explorer_state.dart

import 'dart:async';
import 'package:flutter/foundation.dart'; // For compute
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../utils/file_traversal_util.dart';
import '../../../settings/settings_notifier.dart';
import 'search_explorer_settings.dart';

class SearchResult {
  final ProjectDocumentFile file;
  final int score;

  SearchResult({required this.file, required this.score});
}

class SearchState {
  final String query;
  final List<SearchResult> results;
  final bool isSearching;

  SearchState({this.query = '', this.results = const [], this.isSearching = false});

  SearchState copyWith({String? query, List<SearchResult>? results, bool? isSearching}) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

final searchableFilesProvider =
    FutureProvider.autoDispose<List<ProjectDocumentFile>>((ref) async {
  final project = ref.watch(appNotifierProvider).value?.currentProject;
  
  // FIX: STRICTLY select only the search settings.
  // We use 'select' to ensure we don't rebuild if other plugins update settings.
  final settings = ref.watch(effectiveSettingsProvider.select((s) {
    final config = s.explorerPluginSettings['com.machine.search_explorer'];
    // Ensure we return a comparable object (SearchExplorerSettings) or null
    return config is SearchExplorerSettings ? config : null;
  }));

  final effectiveSettings = settings ?? SearchExplorerSettings();

  if (project == null) {
    return [];
  }

  final List<ProjectDocumentFile> allFiles = [];
  
  await FileTraversalUtil.traverseProject(
    ref: ref,
    startDirectoryUri: project.rootUri,
    supportedExtensions: effectiveSettings.supportedExtensions,
    ignoredGlobPatterns: effectiveSettings.ignoredGlobPatterns,
    useProjectGitignore: effectiveSettings.useProjectGitignore,
    onFileFound: (file, displayPath) async {
      allFiles.add(file);
    },
  );

  return allFiles;
});

final searchStateProvider =
    StateNotifierProvider.autoDispose<SearchStateNotifier, SearchState>(
      (ref) => SearchStateNotifier(ref),
    );

class SearchStateNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  Timer? _debounce;

  SearchStateNotifier(this._ref) : super(SearchState());

  void search(String query) {
    _debounce?.cancel();

    if (query.isEmpty) {
      state = state.copyWith(query: query, results: [], isSearching: false);
      return;
    }

    state = state.copyWith(query: query, isSearching: true);

    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;

      final allFilesAsync = _ref.read(searchableFilesProvider);

      allFilesAsync.when(
        data: (allFiles) async {
          // PERFORMANCE FIX: Run heavy search logic in a background isolate
          final results = await compute(_performFuzzySearch, _SearchArgs(allFiles, query));
          
          if (mounted) {
            state = state.copyWith(results: results, isSearching: false);
          }
        },
        loading: () {}, // Index building
        error: (err, stack) {
          if (mounted) {
            state = state.copyWith(isSearching: false, results: []);
          }
        },
      );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

// --- Isolate Logic Helpers ---

class _SearchArgs {
  final List<ProjectDocumentFile> files;
  final String query;
  _SearchArgs(this.files, this.query);
}

// Top-level function for compute
List<SearchResult> _performFuzzySearch(_SearchArgs args) {
  final lowerCaseQuery = args.query.toLowerCase();
  final List<SearchResult> scoredResults = [];

  for (final file in args.files) {
    final score = _calculateFuzzyScore(
      file.name.toLowerCase(),
      lowerCaseQuery,
    );
    if (score > 0) {
      scoredResults.add(SearchResult(file: file, score: score));
    }
  }

  scoredResults.sort((a, b) => b.score.compareTo(a.score));
  return scoredResults;
}

int _calculateFuzzyScore(String target, String query) {
  if (query.isEmpty) return 1;
  if (target.isEmpty) return 0;

  int score = 0;
  int queryIndex = 0;
  int targetIndex = 0;
  int lastMatchIndex = -1;

  while (queryIndex < query.length && targetIndex < target.length) {
    if (query[queryIndex] == target[targetIndex]) {
      score += 10;

      if (lastMatchIndex == targetIndex - 1) {
        score += 20;
      }

      if (targetIndex > 0) {
        final prevChar = target[targetIndex - 1];
        if (prevChar == '_' || prevChar == '-' || prevChar == ' ') {
          score += 15;
        }
        if (prevChar.toLowerCase() == prevChar &&
            target[targetIndex].toUpperCase() == target[targetIndex]) {
          score += 15;
        }
      }

      if (targetIndex == 0) {
        score += 15;
      }

      lastMatchIndex = targetIndex;
      queryIndex++;
    }
    targetIndex++;
  }

  if (queryIndex != query.length) {
    return 0;
  }

  return score - target.length;
}