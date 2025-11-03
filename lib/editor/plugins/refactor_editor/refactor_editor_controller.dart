// lib/editor/plugins/refactor_editor/refactor_editor_controller.dart

import 'package:flutter/foundation.dart';

import 'refactor_editor_models.dart';

/// A mutable state controller for a single Refactor Editor session.
class RefactorController extends ChangeNotifier {
  String searchTerm;
  String replaceTerm;
  bool isRegex;
  bool isCaseSensitive;
  bool autoOpenFiles;
  RefactorMode mode;
  SearchStatus searchStatus = SearchStatus.idle;

  final List<RefactorResultItem> resultItems = [];
  final Set<RefactorResultItem> selectedItems = {};

  RefactorController({required RefactorSessionState initialState})
    : searchTerm = initialState.searchTerm,
      replaceTerm = initialState.replaceTerm,
      isRegex = initialState.isRegex,
      isCaseSensitive = initialState.isCaseSensitive,
      autoOpenFiles = initialState.autoOpenFiles,
      mode = initialState.mode;

  // --- UI State Mutation Methods ---

  void updateSearchTerm(String term) {
    searchTerm = term;
    notifyListeners();
  }

  void updateReplaceTerm(String term) {
    replaceTerm = term;
    notifyListeners();
  }

  // NEW: Method to set the mode.
  void setMode(RefactorMode newMode) {
    mode = newMode;
    // When switching modes, clear previous results.
    resultItems.clear();
    selectedItems.clear();
    searchStatus = SearchStatus.idle;
    notifyListeners();
  }

  void toggleIsRegex(bool value) {
    isRegex = value;
    notifyListeners();
  }

  void toggleCaseSensitive(bool value) {
    isCaseSensitive = value;
    notifyListeners();
  }

  void toggleAutoOpenFiles(bool value) {
    autoOpenFiles = value;
    notifyListeners();
  }

  void toggleItemSelection(RefactorResultItem item) {
    if (item.status != ResultStatus.pending) return;
    if (selectedItems.contains(item)) {
      selectedItems.remove(item);
    } else {
      selectedItems.add(item);
    }
    notifyListeners();
  }

  void toggleSelectAll(bool isSelected) {
    selectedItems.clear();
    if (isSelected) {
      selectedItems.addAll(
        resultItems.where((item) => item.status == ResultStatus.pending),
      );
    }
    notifyListeners();
  }

  void toggleSelectAllForFile(String fileUri, bool shouldSelect) {
    final itemsForFile = resultItems.where(
      (i) =>
          i.occurrence.fileUri == fileUri && i.status == ResultStatus.pending,
    );

    if (shouldSelect) {
      selectedItems.addAll(itemsForFile);
    } else {
      selectedItems.removeAll(itemsForFile);
    }
    notifyListeners();
  }

  void startSearch() {
    searchStatus = SearchStatus.searching;
    resultItems.clear();
    selectedItems.clear();
    notifyListeners();
  }

  void completeSearch(List<RefactorOccurrence> results) {
    resultItems.addAll(
      results.map((occ) => RefactorResultItem(occurrence: occ)),
    );
    searchStatus = SearchStatus.complete;
    notifyListeners();
  }

  void failSearch() {
    searchStatus = SearchStatus.error;
    notifyListeners();
  }

  void updateItemsStatus({
    required Iterable<RefactorResultItem> processed,
    required Map<RefactorResultItem, String> failed,
  }) {
    final processedSet = processed.toSet();
    for (int i = 0; i < resultItems.length; i++) {
      final currentItem = resultItems[i];
      if (processedSet.contains(currentItem)) {
        resultItems[i] = currentItem.copyWith(status: ResultStatus.applied);
      } else if (failed.containsKey(currentItem)) {
        resultItems[i] = currentItem.copyWith(
          status: ResultStatus.failed,
          failureReason: failed[currentItem],
        );
      }
    }
    selectedItems.clear();
    notifyListeners();
  }

  // --- Core Business Logic (Pure Dart) ---

  List<RefactorOccurrence> searchInContent({
    required String content,
    required String fileUri,
    required String displayPath,
    required String fileContentHash,
  }) {
    if (searchTerm.isEmpty) return [];

    final occurrencesInFile = <RefactorOccurrence>[];
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      Iterable<Match> matches;

      if (isRegex) {
        try {
          matches = RegExp(searchTerm, caseSensitive: isCaseSensitive).allMatches(line);
        } catch (e) {
          matches = [];
        }
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
        // REMOVED: All logic for calculating capture group positions is gone.
        
        occurrencesInFile.add(RefactorOccurrence(
          fileUri: fileUri,
          displayPath: displayPath,
          lineNumber: i,
          startColumn: match.start,
          lineContent: line,
          matchedText: match.group(0)!,
          fileContentHash: fileContentHash,
        ));
      }
    }
    return occurrencesInFile;
  }
}

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
  @override
  String operator [](int group) => this.group(group)!;
}
