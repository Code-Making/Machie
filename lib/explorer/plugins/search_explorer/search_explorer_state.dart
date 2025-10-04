// =========================================
// UPDATED: lib/explorer/plugins/search_explorer/search_explorer_state.dart
// =========================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../project/services/project_file_cache.dart';

// THE FIX: Create a wrapper class to hold the score.
class SearchResult {
  final DocumentFile file;
  final int score;

  SearchResult({required this.file, required this.score});
}

class SearchState {
  final String query;
  // THE FIX: The results are now a list of SearchResult.
  final List<SearchResult> results;

  SearchState({
    this.query = '',
    this.results = const [],
  });

  SearchState copyWith({
    String? query,
    List<SearchResult>? results,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
    );
  }
}

final searchStateProvider =
    NotifierProvider<SearchStateNotifier, SearchState>(
        SearchStateNotifier.new);

class SearchStateNotifier extends Notifier<SearchState> {
  Timer? _debounce;

  @override
  SearchState build() {
    // ADDED: Listen for project changes to clear the search state.
    ref.listen<Project?>(
      appNotifierProvider.select((s) => s.value?.currentProject),
      (previous, next) {
        // If the project changes (or closes), reset to the initial state.
        if (previous?.id != next?.id) {
          state = const SearchState();
        }
      },
    );
    // Return the initial state.
    return const SearchState();
  }

  void search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      state = state.copyWith(query: query);
      
      if (query.isEmpty) {
        // We keep the query text but clear the results.
        state = state.copyWith(results: []);
        return;
      }

      try {
        await ref.read(projectFileCacheProvider.notifier).ensureFullCacheIsBuilt();
        final fileCache = ref.read(projectFileCacheProvider);
        final allFiles = fileCache.directoryContents.values
            .expand((files) => files)
            .where((file) => !file.isDirectory)
            .toList();
        
        // ... (rest of search logic is unchanged)
        final lowerCaseQuery = query.toLowerCase();
        final List<SearchResult> scoredResults = [];
        for (final file in allFiles) {
          final score = _calculateFuzzyScore(file.name.toLowerCase(), lowerCaseQuery);
          if (score > 0) {
            scoredResults.add(SearchResult(file: file, score: score));
          }
        }
        scoredResults.sort((a, b) => b.score.compareTo(a.score));

        state = state.copyWith(results: scoredResults);
      } catch (e) {
        print("Error during file cache build for search: $e");
      }
    });
  }

  int _calculateFuzzyScore(String target, String query) {
    if (query.isEmpty) return 1; // Empty query matches everything
    if (target.isEmpty) return 0; // But can't match an empty target

    int score = 0;
    int queryIndex = 0;
    int targetIndex = 0;
    int lastMatchIndex = -1;

    while (queryIndex < query.length && targetIndex < target.length) {
      if (query[queryIndex] == target[targetIndex]) {
        score += 10; // Base score for a match

        // Contiguous bonus
        if (lastMatchIndex == targetIndex - 1) {
          score += 20;
        }

        // Separator/CamelCase bonus
        if (targetIndex > 0) {
          final prevChar = target[targetIndex - 1];
          if (prevChar == '_' || prevChar == '-' || prevChar == ' ') {
            score += 15;
          }
          if (prevChar.toLowerCase() == prevChar && target[targetIndex].toUpperCase() == target[targetIndex]) {
             score += 15; // CamelCase bonus
          }
        }
        
        // First letter bonus
        if (targetIndex == 0) {
          score += 15;
        }

        lastMatchIndex = targetIndex;
        queryIndex++;
      }
      targetIndex++;
    }

    // If we didn't find all characters of the query, it's not a match.
    if (queryIndex != query.length) {
      return 0;
    }

    // Apply a penalty based on the length of the target string.
    // This makes shorter, more exact matches score higher.
    return score - target.length;
  }
  // dispose() is no longer needed as Notifier handles this.
  // @override
  // void dispose() {
  //   _debounce?.cancel();
  //   super.dispose();
  // }
}