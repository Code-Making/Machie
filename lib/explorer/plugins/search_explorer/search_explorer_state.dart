// =========================================
// UPDATED: lib/explorer/plugins/search_explorer/search_explorer_state.dart
// =========================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../project/services/project_file_index.dart';

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
    StateNotifierProvider.autoDispose<SearchStateNotifier, SearchState>(
  (ref) => SearchStateNotifier(ref),
);

class SearchStateNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  Timer? _debounce;

  SearchStateNotifier(this._ref) : super(SearchState());

  void search(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;

      final allFiles = _ref.read(projectFileIndexProvider).valueOrNull ?? [];
      state = state.copyWith(query: query);

      if (query.isEmpty) {
        state = state.copyWith(results: []);
        return;
      }

      // THE FIX: Use the new fuzzy search algorithm.
      final lowerCaseQuery = query.toLowerCase();
      final List<SearchResult> scoredResults = [];

      for (final file in allFiles) {
        final score = _calculateFuzzyScore(file.name.toLowerCase(), lowerCaseQuery);
        // Only include results that are actual matches (score > 0).
        if (score > 0) {
          scoredResults.add(SearchResult(file: file, score: score));
        }
      }

      // Sort results by score in descending order.
      scoredResults.sort((a, b) => b.score.compareTo(a.score));

      if (mounted) {
        state = state.copyWith(results: scoredResults);
      }
    });
  }

  // THE FIX: The core fuzzy matching and scoring algorithm.
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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}