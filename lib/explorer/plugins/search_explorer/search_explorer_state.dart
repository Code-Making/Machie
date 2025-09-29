// =========================================
// UPDATED: lib/explorer/plugins/search_explorer/search_explorer_state.dart
// =========================================

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../project/services/project_file_index.dart'; // IMPORT THE NEW SERVICE

class SearchState {
  final String query;
  final List<DocumentFile> results;

  // isLoading is removed, as this will be handled by the view watching the index provider.
  SearchState({
    this.query = '',
    this.results = const [],
  });

  SearchState copyWith({
    String? query,
    List<DocumentFile>? results,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
    );
  }
}

// REFACTORED: No longer a family provider. It's a simple, auto-disposing provider.
final searchStateProvider =
    StateNotifierProvider.autoDispose<SearchStateNotifier, SearchState>(
  (ref) => SearchStateNotifier(ref),
);

// REFACTORED: This notifier is now very simple. Its only job is to filter.
class SearchStateNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  Timer? _debounce;

  SearchStateNotifier(this._ref) : super(SearchState());

  void search(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;

      // Get the full, up-to-date list of files from the index service.
      final allFiles = _ref.read(projectFileIndexProvider).valueOrNull ?? [];

      state = state.copyWith(query: query);

      if (query.isEmpty) {
        state = state.copyWith(results: []);
        return;
      }

      final lowerCaseQuery = query.toLowerCase();
      final results = allFiles
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