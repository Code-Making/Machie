// =========================================
// CORRECTED: lib/editor/plugins/refactor_editor/refactor_editor_controller.dart
// =========================================
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glob/glob.dart';
import 'package:collection/collection.dart'; // For firstWhereOrNull

import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project_repository.dart';
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
  
  Future<List<RefactorOccurrence>> findOccurrences({
    required RefactorSettings settings,
    required ProjectRepository repo,
    required String projectRootUri,
    required NotifierProvider<ProjectHierarchyService, Map<String, AsyncValue<List<FileTreeNode>>>> hierarchyProvider,
  }) async {
    if (searchTerm.isEmpty) return [];

    final foundOccurrences = <RefactorOccurrence>[];
    
    // 1. Pre-compile global ignore patterns
    final List<Glob> globalIgnoreGlobs = settings.ignoredGlobPatterns.map((p) => Glob(p)).toList();

    // 2. Define the recursive traversal function
    Future<void> traverse(String dirUri, List<Glob> inheritedGlobs) async {
      // Get children for the current directory from the hierarchy service
      final childrenResult = await _ref.read(hierarchyProvider.notifier).loadDirectory(dirUri);
      if (childrenResult == null) return;

      final List<FileTreeNode> children = childrenResult;
      
      // Check for a .gitignore in the current directory
      List<Glob> currentGlobs = List.from(inheritedGlobs);
      if (settings.useProjectGitignore) {
        final gitignoreNode = children.firstWhere((node) => node.file.name == '.gitignore', orElse: () => FileTreeNode(VirtualDocumentFile(uri: '', name: '')));
        if (gitignoreNode.file.name == '.gitignore') {
          try {
            final content = await repo.readFile(gitignoreNode.file.uri);
            final patterns = content.split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty && !line.startsWith('#'));
            currentGlobs.addAll(patterns.map((p) => Glob(p)));
          } catch (_) {}
        }
      }

      // Process children
      for (final node in children) {
        final file = node.file;
        final relativePath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: projectRootUri);
        
        // --- HIERARCHICAL IGNORE LOGIC ---
        // Check against global ignores first
        if (globalIgnoreGlobs.any((glob) => glob.matches(relativePath))) {
          continue;
        }
        // Then check against inherited/current gitignore patterns
        if (currentGlobs.any((glob) => glob.matches(file.name))) {
          continue;
        }

        if (file.isDirectory) {
          // If it's a directory and not ignored, traverse into it
          await traverse(file.uri, currentGlobs);
        } else {
          // It's a file, check extension and then search content
          if (settings.supportedExtensions.any((ext) => relativePath.endsWith(ext))) {
            await _searchFileContent(file, relativePath, foundOccurrences, repo);
          }
        }
      }
    }

    // 3. Start the traversal from the project root
    await traverse(projectRootUri, []);

    return foundOccurrences;
  }
  
  /// Helper function to search inside a single valid file.
  Future<void> _searchFileContent(
    ProjectDocumentFile file,
    String relativePath,
    List<RefactorOccurrence> foundOccurrences,
    ProjectRepository repo
  ) async {
      final content = await repo.readFile(file.uri);
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
            displayPath: relativePath,
            lineNumber: i + 1, startColumn: match.start, lineContent: line, matchedText: match.group(0)!,
          ));
        }
      }
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