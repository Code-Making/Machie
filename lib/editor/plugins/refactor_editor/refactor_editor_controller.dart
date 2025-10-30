// =========================================
// RENAMED & REFACTORED: lib/editor/plugins/refactor_editor/refactor_editor_controller.dart
// =========================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/project_repository.dart';
import '../../../logs/logs_provider.dart';
import '../../../project/services/project_hierarchy_service.dart';
import '../../../settings/settings_notifier.dart';
import 'refactor_editor_models.dart';

/// A mutable state controller for a single Refactor Editor session.
/// It uses ChangeNotifier to efficiently notify the UI of updates without
/// expensive state copying.
class RefactorController extends ChangeNotifier {
  final Ref _ref;
  
  // State properties are now public and mutable.
  String searchTerm;
  String replaceTerm;
  bool isRegex;
  bool isCaseSensitive;
  SearchStatus searchStatus = SearchStatus.idle;
  
  final List<RefactorOccurrence> occurrences = [];
  final Set<RefactorOccurrence> selectedOccurrences = {};

  RefactorController(this._ref, {required RefactorSessionState initialState})
      : searchTerm = initialState.searchTerm,
        replaceTerm = initialState.replaceTerm,
        isRegex = initialState.isRegex,
        isCaseSensitive = initialState.isCaseSensitive;

  void updateSearchTerm(String term) {
    searchTerm = term;
    // No need to notify listeners for simple text changes.
  }

  void updateReplaceTerm(String term) {
    replaceTerm = term;
  }

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

  Future<void> findOccurrences() async {
    if (searchTerm.isEmpty) return;

    searchStatus = SearchStatus.searching;
    occurrences.clear();
    selectedOccurrences.clear();
    notifyListeners();

    try {
      final repo = _ref.read(projectRepositoryProvider);
      final allFiles = _ref.read(flatFileIndexProvider).valueOrNull ?? [];
      final settings = _ref.read(settingsProvider).pluginSettings[RefactorSettings] as RefactorSettings?;
      if (repo == null || settings == null || allFiles.isEmpty) {
        throw Exception('Project, settings, or file index not available');
      }
      final projectRootUri = repo.fileHandler.getParentUri(allFiles.first.uri);

      final foundOccurrences = <RefactorOccurrence>[];

      final filteredFiles = allFiles.where((file) {
        final path = file.uri;
        final hasValidExtension = settings.supportedExtensions.any((ext) => path.endsWith(ext));
        final isIgnored = settings.ignoredFolders.any((folder) => path.contains('/$folder/'));
        return hasValidExtension && !isIgnored;
      }).toList();

      for (final file in filteredFiles) {
        final content = await repo.readFile(file.uri);
        final lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final Iterable<Match> matches;
          if (isRegex) {
            matches = RegExp(searchTerm, caseSensitive: isCaseSensitive).allMatches(line);
          } else {
            // This can be optimized, but is fine for now.
            final tempMatches = <Match>[];
            int startIndex = 0;
            final query = isCaseSensitive ? searchTerm : searchTerm.toLowerCase();
            final target = isCaseSensitive ? line : line.toLowerCase();
            while (startIndex < target.length) {
              final index = target.indexOf(query, startIndex);
              if (index == -1) break;
              tempMatches.add(_StringMatch(index, line.substring(index, index + searchTerm.length)));
              startIndex = index + searchTerm.length;
            }
            matches = tempMatches;
          }

          for (final match in matches) {
            foundOccurrences.add(RefactorOccurrence(
              fileUri: file.uri,
              displayPath: repo.fileHandler.getPathForDisplay(file.uri, relativeTo: projectRootUri),
              lineNumber: i + 1, startColumn: match.start, lineContent: line, matchedText: match.group(0)!,
            ));
          }
        }
      }
      
      occurrences.addAll(foundOccurrences);
      searchStatus = SearchStatus.complete;
    } catch (e, st) {
      _ref.read(talkerProvider).handle(e, st, '[Refactor] Search failed');
      searchStatus = SearchStatus.error;
    } finally {
      notifyListeners();
    }
  }

  // Placeholder for the apply logic
  Future<void> applyChanges() async {
    // TODO: Implement apply logic
  }
}

// Helper class to mimic the 'Match' interface for simple string searches.
class _StringMatch implements Match {
  @override
  final int start;
  final String _text;
  _StringMatch(this.start, this._text);
  @override int get end => start + _text.length;
  @override String? group(int group) => group == 0 ? _text : null;
  @override List<String?> get groups => throw UnimplementedError();
  @override int get groupCount => 0;
  @override String get input => throw UnimplementedError();
  @override Pattern get pattern => throw UnimplementedError();
}