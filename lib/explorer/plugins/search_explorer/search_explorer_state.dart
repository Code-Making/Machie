// =========================================
// FINAL CORRECTED FILE: lib/explorer/plugins/search_explorer/search_explorer_state.dart
// =========================================
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart'; // CORRECTED: Added this import
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/project/project_models.dart';
import 'package:machine/project/services/project_file_cache.dart';

class SearchResult {
  final DocumentFile file;
  final int score;
  SearchResult({required this.file, required this.score});
}

class SearchState {
  final String query;
  final List<SearchResult> results;

  // The constructor is not const
  SearchState({this.query = '', this.results = const []});

  SearchState copyWith({String? query, List<SearchResult>? results}) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
    );
  }
}

final searchStateProvider =
    NotifierProvider<SearchStateNotifier, SearchState>(SearchStateNotifier.new);

class SearchStateNotifier extends Notifier<SearchState> {
  Timer? _debounce;

  @override
  SearchState build() {
    ref.listen<Project?>(
      appNotifierProvider.select((s) => s.value?.currentProject),
      (previous, next) {
        if (previous?.id != next?.id) {
          // CORRECTED: Removed 'const'
          state = SearchState();
        }
      },
    );
    // CORRECTED: Removed 'const'
    return SearchState();
  }

  void search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      state = state.copyWith(query: query);

      if (query.isEmpty) {
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
}