// lib/explorer/plugins/search_explorer/search_explorer_state.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../project/project_models.dart';

// Represents the state of the search explorer
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

// Manages the search logic
final searchStateProvider = StateNotifierProvider.autoDispose
    .family<SearchStateNotifier, SearchState, Project>((ref, project) {
      return SearchStateNotifier(project.fileHandler, project.rootUri);
    });

class SearchStateNotifier extends StateNotifier<SearchState> {
  final FileHandler _fileHandler;
  final String _rootUri;
  List<DocumentFile>? _allFilesCache; // Cache the full file list
  Timer? _debounce;

  SearchStateNotifier(this._fileHandler, this._rootUri) : super(SearchState());

  // Recursively get all files in the project.
  Future<void> _fetchAllFiles() async {
    state = state.copyWith(isLoading: true);
    final allFiles = <DocumentFile>[];
    final directoriesToScan = <String>[_rootUri];

    while (directoriesToScan.isNotEmpty) {
      final currentDirUri = directoriesToScan.removeAt(0);
        final items = await _fileHandler.listDirectory(currentDirUri);
        for (final item in items) {
          if (item.isDirectory) {
            directoriesToScan.add(item.uri);
          } else {
            allFiles.add(item);
          }
        }
        //print('Error scanning directory $currentDirUri: $e');
    }
    _allFilesCache = allFiles;
    state = state.copyWith(isLoading: false);
  }

  // Perform a search with debouncing to avoid excessive searching while typing.
  void search(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      state = state.copyWith(query: query);
      if (query.isEmpty) {
        state = state.copyWith(results: []);
        return;
      }

      if (_allFilesCache == null) {
        await _fetchAllFiles();
      }

      final lowerCaseQuery = query.toLowerCase();
      final results =
          _allFilesCache!
              .where((file) => file.name.toLowerCase().contains(lowerCaseQuery))
              .toList();

      state = state.copyWith(results: results);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
