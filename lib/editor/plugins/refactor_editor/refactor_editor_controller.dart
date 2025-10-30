// =========================================
// CORRECTED: lib/editor/plugins/refactor_editor/refactor_editor_controller.dart
// =========================================

import 'package:flutter/foundation.dart';
import 'package:machine/data/file_handler/file_handler.dart';

import 'refactor_editor_models.dart';

/// A mutable state controller for a single Refactor Editor session.
/// It contains only pure Dart logic and is decoupled from Riverpod.
class RefactorController extends ChangeNotifier {
  // State properties remain public and mutable.
  String searchTerm;
  String replaceTerm;
  bool isRegex;
  bool isCaseSensitive;
  SearchStatus searchStatus = SearchStatus.idle;
  
  final List<RefactorOccurrence> occurrences = [];
  final Set<RefactorOccurrence> selectedOccurrences = {};

  RefactorController({required RefactorSessionState initialState})
      : searchTerm = initialState.searchTerm,
        replaceTerm = initialState.replaceTerm,
        isRegex = initialState.isRegex,
        isCaseSensitive = initialState.isCaseSensitive;

  // --- UI State Mutation Methods ---
  
  void updateSearchTerm(String term) => searchTerm = term;
  void updateReplaceTerm(String term) => replaceTerm = term;

  void toggleIsRegex(bool value) {
    isRegex = value;
    notifyListeners();
  }

  void toggleCaseSensitive(bool value) {
    isCaseSensitive = value;
    notifyListeners();
  }

  void toggleOccurrenceSelection(RefactorOccurrence occurrence) {
    if (selectedOccurrences.contains(occurrence)) {
      selectedOccurrences.remove(occurrence);
    } else {
      selectedOccurrences.add(occurrence);
    }
    notifyListeners();
  }

  void toggleSelectAll(bool isSelected) {
    if (isSelected) {
      selectedOccurrences.addAll(occurrences);
    } else {
      selectedOccurrences.clear();
    }
    notifyListeners();
  }

  void startSearch() {
    searchStatus = SearchStatus.searching;
    occurrences.clear();
    selectedOccurrences.clear();
    notifyListeners();
  }
  
  void completeSearch(List<RefactorOccurrence> results) {
    occurrences.addAll(results);
    searchStatus = SearchStatus.complete;
    notifyListeners();
  }
  
  void failSearch() {
    searchStatus = SearchStatus.error;
    notifyListeners();
  }

  // --- Core Business Logic (Pure Dart) ---
  
  /// Performs the search logic and returns the results. Does not mutate state.
  Future<List<RefactorOccurrence>> findOccurrences({
    required List<ProjectDocumentFile> allFiles,
    required RefactorSettings settings,
    required Future<String> Function(String uri) fileReader,
    required String Function(String uri, {String? relativeTo}) pathDisplayer,
    required String projectRootUri,
  }) async {
    if (searchTerm.isEmpty) return [];

    final foundOccurrences = <RefactorOccurrence>[];

    final filteredFiles = allFiles.where((file) {
      final path = file.uri;
      final hasValidExtension = settings.supportedExtensions.any((ext) => path.endsWith(ext));
      final isIgnored = settings.ignoredFolders.any((folder) => path.contains('/$folder/'));
      return hasValidExtension && !isIgnored;
    }).toList();

    for (final file in filteredFiles) {
      final content = await fileReader(file.uri);
      final lines = content.split('\n');

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final Iterable<Match> matches;
        if (isRegex) {
          matches = RegExp(searchTerm, caseSensitive: isCaseSensitive).allMatches(line);
        } else {
          final tempMatches = <Match>[];
          int startIndex = 0;
          final query = isCaseSensitive ? searchTerm : searchTerm.toLowerCase();
          final target = isCaseSensitive ? line : line.toLowerCase();
          while (startIndex < target.length) {
            final index = target.indexOf(query, startIndex);
            if (index == -1) break;
            tempMatches.add(_StringMatch(line, index, line.substring(index, index + searchTerm.length)));
            startIndex = index + searchTerm.length;
          }
          matches = tempMatches;
        }

        for (final match in matches) {
          foundOccurrences.add(RefactorOccurrence(
            fileUri: file.uri,
            displayPath: pathDisplayer(file.uri, relativeTo: projectRootUri),
            lineNumber: i + 1, startColumn: match.start, lineContent: line, matchedText: match.group(0)!,
          ));
        }
      }
    }
    return foundOccurrences;
  }
  
  // Placeholder for the apply logic
  Future<void> applyChanges() async {
    // TODO: Implement apply logic
  }
}

// CORRECTED: Fully implemented _StringMatch helper class.
class _StringMatch implements Match {
  @override
  final String input;
  @override
  final int start;
  final String _text;

  _StringMatch(this.input, this.start, this._text);

  @override
  int get end => start + _text.length;
  @override
  String? group(int group) => group == 0 ? _text : null;
  @override
  List<String?> groups(List<int> groupIndices) => groupIndices.map(group).toList();
  @override
  int get groupCount => 0;
  @override
  Pattern get pattern => throw UnimplementedError();
  
  // THIS IS THE FIX: It should call the 'group' method on the current instance.
  @override
  String operator [](int group) => this.group(group)!;
}