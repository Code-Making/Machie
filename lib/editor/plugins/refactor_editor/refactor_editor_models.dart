// =========================================
// NEW FILE: lib/editor/plugins/refactor_editor/refactor_editor_models.dart
// =========================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../editor/editor_tab_models.dart';
import '../../../editor/plugins/plugin_models.dart';
import 'refactor_editor_widget.dart';

/// Defines the settings for the Refactor Editor plugin.
class RefactorSettings extends PluginSettings {
  Set<String> supportedExtensions;
  Set<String> ignoredGlobPatterns;
  bool useProjectGitignore; // <-- ADDED

  RefactorSettings({
    Set<String>? supportedExtensions,
    Set<String>? ignoredGlobPatterns,
    this.useProjectGitignore = true, // <-- ADDED, default to true for convenience
  })  : supportedExtensions = supportedExtensions ?? {'.dart', '.yaml', '.md', '.txt', '.json'},
        ignoredGlobPatterns = ignoredGlobPatterns ?? {'.git/**', '.idea/**', 'build/**', '.dart_tool/**'};

  @override
  void fromJson(Map<String, dynamic> json) {
    final legacyIgnored = List<String>.from(json['ignoredFolders'] ?? []);
    final currentIgnored = List<String>.from(json['ignoredGlobPatterns'] ?? []);
    
    supportedExtensions = Set<String>.from(json['supportedExtensions'] ?? []);
    ignoredGlobPatterns = {...legacyIgnored, ...currentIgnored}.toSet();
    useProjectGitignore = json['useProjectGitignore'] as bool? ?? true; // <-- ADDED
  }

  @override
  Map<String, dynamic> toJson() => {
        'supportedExtensions': supportedExtensions.toList(),
        'ignoredGlobPatterns': ignoredGlobPatterns.toList(),
        'useProjectGitignore': useProjectGitignore, // <-- ADDED
      };
}

/// Represents a single occurrence of a search term within a file.
@immutable
class RefactorOccurrence {
  final String fileUri;
  final String displayPath;
  final int lineNumber; // 1-based
  final int startColumn; // 0-based
  final String lineContent;
  final String matchedText;

  const RefactorOccurrence({
    required this.fileUri,
    required this.displayPath,
    required this.lineNumber,
    required this.startColumn,
    required this.lineContent,
    required this.matchedText,
  });
}

/// Represents the live state of a refactoring session.
@immutable
class RefactorSessionState {
  final String searchTerm;
  final String replaceTerm;
  final bool isRegex;
  final bool isCaseSensitive;
  final SearchStatus searchStatus;
  final List<RefactorOccurrence> occurrences;
  final Set<RefactorOccurrence> selectedOccurrences;

  const RefactorSessionState({
    this.searchTerm = '',
    this.replaceTerm = '',
    this.isRegex = false,
    this.isCaseSensitive = false,
    this.searchStatus = SearchStatus.idle,
    this.occurrences = const [],
    this.selectedOccurrences = const {},
  });

  RefactorSessionState copyWith({
    String? searchTerm,
    String? replaceTerm,
    bool? isRegex,
    bool? isCaseSensitive,
    SearchStatus? searchStatus,
    List<RefactorOccurrence>? occurrences,
    Set<RefactorOccurrence>? selectedOccurrences,
  }) {
    return RefactorSessionState(
      searchTerm: searchTerm ?? this.searchTerm,
      replaceTerm: replaceTerm ?? this.replaceTerm,
      isRegex: isRegex ?? this.isRegex,
      isCaseSensitive: isCaseSensitive ?? this.isCaseSensitive,
      searchStatus: searchStatus ?? this.searchStatus,
      occurrences: occurrences ?? this.occurrences,
      selectedOccurrences: selectedOccurrences ?? this.selectedOccurrences,
    );
  }
}

enum SearchStatus { idle, searching, complete, error }

/// The concrete EditorTab for the Refactor Editor.
class RefactorEditorTab extends EditorTab {
  @override
  final GlobalKey<RefactorEditorWidgetState> editorKey;
  final RefactorSessionState initialState;

  RefactorEditorTab({
    required super.plugin,
    required this.initialState,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<RefactorEditorWidgetState>();

  @override
  void dispose() {
    // No special disposal needed for this tab itself.
  }
}