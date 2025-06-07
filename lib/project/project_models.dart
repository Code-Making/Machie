// lib/project/project_models.dart

import 'dart:convert';

import 'package:flutter/material.dart'; // For IconData
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --------------------
// Project Data Models
// --------------------

/// Represents simplified metadata for a project stored globally (e.g., in SharedPreferences).
/// Used for listing known projects without loading their full state.
class ProjectMetadata {
  final String id; // Unique ID for the project
  final String name; // User-friendly name
  final String rootUri; // SAF URI to the project's root folder
  final DateTime lastOpenedDateTime; // Timestamp for sorting recent projects
  final int? lastOpenedTabIndex; // Index of the last active tab
  final String? lastOpenedFileUri; // URI of the last active file

  ProjectMetadata({
    required this.id,
    required this.name,
    required this.rootUri,
    required this.lastOpenedDateTime,
    this.lastOpenedTabIndex,
    this.lastOpenedFileUri,
  });

  ProjectMetadata copyWith({
    String? id,
    String? name,
    String? rootUri,
    DateTime? lastOpenedDateTime,
    int? lastOpenedTabIndex,
    String? lastOpenedFileUri,
  }) {
    return ProjectMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      rootUri: rootUri ?? this.rootUri,
      lastOpenedDateTime: lastOpenedDateTime ?? this.lastOpenedDateTime,
      lastOpenedTabIndex: lastOpenedTabIndex ?? this.lastOpenedTabIndex,
      lastOpenedFileUri: lastOpenedFileUri ?? this.lastOpenedFileUri,
    );
  }

  factory ProjectMetadata.fromJson(Map<String, dynamic> json) {
    return ProjectMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      rootUri: json['rootUri'] as String,
      lastOpenedDateTime: DateTime.parse(json['lastOpenedDateTime'] as String),
      lastOpenedTabIndex: json['lastOpenedTabIndex'] as int?,
      lastOpenedFileUri: json['lastOpenedFileUri'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'rootUri': rootUri,
      'lastOpenedDateTime': lastOpenedDateTime.toIso8601String(),
      'lastOpenedTabIndex': lastOpenedTabIndex,
      'lastOpenedFileUri': lastOpenedFileUri,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectMetadata &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Represents the full state of an actively loaded project.
/// This data is saved/loaded from the project's .machine folder.
class Project {
  final String id;
  final String name;
  final String rootUri;
  final String projectDataPath; // URI to the .machine folder
  final Set<String> expandedFolders; // URIs of currently expanded folders in the tree
  final FileExplorerViewMode fileExplorerViewMode; // Current view/sort mode
  final Map<String, dynamic> sessionData; // Generic map for plugin-specific session data (e.g., last opened files)
  final int filesCount; // New: Cached total file count for display
  final int foldersCount; // New: Cached total folder count for display

  Project({
    required this.id,
    required this.name,
    required this.rootUri,
    required this.projectDataPath,
    Set<String>? expandedFolders,
    FileExplorerViewMode? fileExplorerViewMode,
    Map<String, dynamic>? sessionData,
    this.filesCount = 0, // Initialize count
    this.foldersCount = 0, // Initialize count
  }) : expandedFolders = expandedFolders ?? {},
       fileExplorerViewMode = fileExplorerViewMode ?? FileExplorerViewMode.sortByNameAsc,
       sessionData = sessionData ?? {};

  Project copyWith({
    String? id,
    String? name,
    String? rootUri,
    String? projectDataPath,
    Set<String>? expandedFolders,
    FileExplorerViewMode? fileExplorerViewMode,
    Map<String, dynamic>? sessionData,
    int? filesCount, // Include in copyWith
    int? foldersCount, // Include in copyWith
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      rootUri: rootUri ?? this.rootUri,
      projectDataPath: projectDataPath ?? this.projectDataPath,
      expandedFolders: expandedFolders ?? this.expandedFolders,
      fileExplorerViewMode: fileExplorerViewMode ?? this.fileExplorerViewMode,
      sessionData: sessionData ?? this.sessionData,
      filesCount: filesCount ?? this.filesCount,
      foldersCount: foldersCount ?? this.foldersCount,
    );
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      rootUri: json['rootUri'] as String,
      projectDataPath: json['projectDataPath'] as String,
      expandedFolders: (json['expandedFolders'] as List<dynamic>?)?.map((e) => e as String).toSet() ?? {},
      fileExplorerViewMode: FileExplorerViewMode.values.firstWhere(
        (e) => e.toString() == json['fileExplorerViewMode'],
        orElse: () => FileExplorerViewMode.sortByNameAsc,
      ),
      sessionData: (json['sessionData'] as Map<String, dynamic>?) ?? {},
      filesCount: json['filesCount'] as int? ?? 0, // Deserialize count
      foldersCount: json['foldersCount'] as int? ?? 0, // Deserialize count
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'rootUri': rootUri,
      'projectDataPath': projectDataPath,
      'expandedFolders': expandedFolders.toList(),
      'fileExplorerViewMode': fileExplorerViewMode.toString(),
      'sessionData': sessionData,
      'filesCount': filesCount, // Serialize count
      'foldersCount': foldersCount, // Serialize count
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Defines different modes for the file explorer view/sorting.
enum FileExplorerViewMode {
  // Sorting options
  sortByNameAsc('Sort by Name (A-Z)', Icons.sort_by_alpha),
  sortByNameDesc('Sort by Name (Z-A)', Icons.sort_by_alpha),
  sortByDateModifiedDesc('Sort by Date (Newest)', Icons.access_time),
  sortByDateModifiedAsc('Sort by Date (Oldest)', Icons.access_time),
  // Filtering options
  showAllFiles('Show All Files', Icons.folder),
  showOnlyCodeFiles('Show Only Code', Icons.code),
  // Add more as needed (e.g., grid view, search results)
  ;

  final String label;
  final IconData icon;

  const FileExplorerViewMode(this.label, this.icon);
}


/// Represents an item currently held in the clipboard for cut/copy/paste operations.
enum ClipboardOperation { cut, copy }

class ClipboardItem {
  final String uri;
  final bool isFolder;
  final ClipboardOperation operation;
  final String name; // New: Add name for display in paste dialog/UI

  ClipboardItem({
    required this.uri,
    required this.isFolder,
    required this.operation,
    required this.name,
  });

  ClipboardItem copyWith({
    String? uri,
    bool? isFolder,
    ClipboardOperation? operation,
    String? name,
  }) {
    return ClipboardItem(
      uri: uri ?? this.uri,
      isFolder: isFolder ?? this.isFolder,
      operation: operation ?? this.operation,
      name: name ?? this.name,
    );
  }
}

// --------------------
// Project-related Providers
// --------------------

/// Provider for the internal clipboard state.
final clipboardProvider = StateProvider<ClipboardItem?>((ref) => null);