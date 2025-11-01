// lib/editor/plugins/refactor_editor/refactor_editor_controller.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart'; 

import 'refactor_editor_models.dart';

/// A mutable state controller for a single Refactor Editor session.
/// It contains only pure Dart logic and is decoupled from Riverpod.
class RefactorController extends ChangeNotifier {
  String searchTerm;
  String replaceTerm;
  bool isRegex;
  bool isCaseSensitive;
  SearchStatus searchStatus = SearchStatus.idle;
  
  // UPDATED: The controller now manages a list of stateful items.
  final List<RefactorResultItem> resultItems = [];
  final Set<RefactorResultItem> selectedItems = {};

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

  void toggleItemSelection(RefactorResultItem item) {
    // Only selectable if pending
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
      // Only select items that are still pending
      selectedItems.addAll(resultItems.where((item) => item.status == ResultStatus.pending));
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
    // Map the raw data into our new stateful wrapper class.
    resultItems.addAll(results.map((occ) => RefactorResultItem(occurrence: occ)));
    searchStatus = SearchStatus.complete;
    notifyListeners();
  }
  
  void failSearch() {
    searchStatus = SearchStatus.error;
    notifyListeners();
  }
  
  // NEW: A method to update the status of items after an operation.
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
    required String fileContentHash, // Pass in the hash
  }) {
    if (searchTerm.isEmpty) return [];

    final occurrencesInFile = <RefactorOccurrence>[];
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
        occurrencesInFile.add(RefactorOccurrence(
          fileUri: fileUri,
          displayPath: displayPath,
          lineNumber: i,
          startColumn: match.start,
          lineContent: line,
          matchedText: match.group(0)!,
          fileContentHash: fileContentHash, // Store the hash
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