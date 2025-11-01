// lib/editor/plugins/refactor_editor/refactor_editor_models.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../editor/editor_tab_models.dart';
import '../../../editor/plugins/plugin_models.dart';
import 'refactor_editor_widget.dart';

/// Defines the settings for the Refactor Editor plugin.
class RefactorSettings extends PluginSettings {
  Set<String> supportedExtensions;
  Set<String> ignoredGlobPatterns;
  bool useProjectGitignore;

  RefactorSettings({
    Set<String>? supportedExtensions,
    Set<String>? ignoredGlobPatterns,
    this.useProjectGitignore = true,
  })  : supportedExtensions = supportedExtensions ?? {'.dart', '.yaml', '.md', '.txt', '.json'},
        ignoredGlobPatterns = ignoredGlobPatterns ?? {'.git/**', '.idea/**', 'build/**', '.dart_tool/**'};

  @override
  void fromJson(Map<String, dynamic> json) {
    final legacyIgnored = List<String>.from(json['ignoredFolders'] ?? []);
    final currentIgnored = List<String>.from(json['ignoredGlobPatterns'] ?? []);
    
    supportedExtensions = Set<String>.from(json['supportedExtensions'] ?? []);
    ignoredGlobPatterns = {...legacyIgnored, ...currentIgnored}.toSet();
    useProjectGitignore = json['useProjectGitignore'] as bool? ?? true;
  }

  @override
  Map<String, dynamic> toJson() => {
        'supportedExtensions': supportedExtensions.toList(),
        'ignoredGlobPatterns': ignoredGlobPatterns.toList(),
        'useProjectGitignore': useProjectGitignore,
      };
}

/// Represents a single occurrence of a search term within a file.
@immutable
class RefactorOccurrence {
  final String fileUri;
  final String displayPath;
  final int lineNumber; // 0-based
  final int startColumn; // 0-based
  final String lineContent;
  final String matchedText;
  final String fileContentHash;

  const RefactorOccurrence({
    required this.fileUri,
    required this.displayPath,
    required this.lineNumber,
    required this.startColumn,
    required this.lineContent,
    required this.matchedText,
    required this.fileContentHash,
  });
}

/// An enum to track the state of a result item in the UI.
enum ResultStatus { pending, applied, failed }

/// A wrapper class to hold an occurrence and its UI state.
@immutable
class RefactorResultItem {
  final RefactorOccurrence occurrence;
  final ResultStatus status;
  final String? failureReason;

  const RefactorResultItem({
    required this.occurrence,
    this.status = ResultStatus.pending,
    this.failureReason,
  });

  RefactorResultItem copyWith({
    ResultStatus? status,
    String? failureReason,
  }) {
    return RefactorResultItem(
      occurrence: occurrence,
      status: status ?? this.status,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}

enum RefactorMode { text, path }

/// Represents the live state of a refactoring session.
@immutable
class RefactorSessionState {
  final String searchTerm;
  final String replaceTerm;
  final bool isRegex;
  final bool isCaseSensitive;
  final bool autoOpenFiles;
  final RefactorMode mode;

  const RefactorSessionState({
    this.searchTerm = '',
    this.replaceTerm = '',
    this.isRegex = false,
    this.isCaseSensitive = false,
    this.autoOpenFiles = true,
    this.mode = RefactorMode.text,
  });
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