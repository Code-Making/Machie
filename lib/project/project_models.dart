// lib/project/project_models.dart

import 'package:flutter/material.dart'; // For IconData
import 'package:flutter_riverpod/flutter_riverpod.dart'; // For StateProvider
import 'package:uuid/uuid.dart'; // Add uuid: ^4.0.0 to pubspec.yaml

import '../file_system/file_handler.dart'; // For DocumentFile

// --------------------
// Project Models
// --------------------

class ProjectMetadata {
  final String id;
  final String name;
  final String rootUri;
  final DateTime lastOpenedDateTime;
  final int? lastOpenedTabIndex;
  final String? lastOpenedFileUri;

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootUri': rootUri,
        'lastOpenedDateTime': lastOpenedDateTime.toIso8601String(),
        'lastOpenedTabIndex': lastOpenedTabIndex,
        'lastOpenedFileUri': lastOpenedFileUri,
      };

  factory ProjectMetadata.fromJson(Map<String, dynamic> json) {
    return ProjectMetadata(
      id: json['id'],
      name: json['name'],
      rootUri: json['rootUri'],
      lastOpenedDateTime: DateTime.parse(json['lastOpenedDateTime']),
      lastOpenedTabIndex: json['lastOpenedTabIndex'],
      lastOpenedFileUri: json['lastOpenedFileUri'],
    );
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

class Project {
  final String id;
  String name;
  String rootUri;
  String projectDataPath; // URI to the .machine folder
  Set<String> expandedFolders; // URIs of currently expanded folders in tree view
  FileExplorerViewMode fileExplorerViewMode; // Current view mode for explorer
  Map<String, dynamic> sessionData; // Generic map for plugin-specific session data

  Project({
    required this.id,
    required this.name,
    required this.rootUri,
    required this.projectDataPath,
    Set<String>? expandedFolders,
    this.fileExplorerViewMode = FileExplorerViewMode.sortByNameAsc,
    Map<String, dynamic>? sessionData,
  })  : expandedFolders = expandedFolders ?? {},
        sessionData = sessionData ?? {};

  Project copyWith({
    String? id,
    String? name,
    String? rootUri,
    String? projectDataPath,
    Set<String>? expandedFolders,
    FileExplorerViewMode? fileExplorerViewMode,
    Map<String, dynamic>? sessionData,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      rootUri: rootUri ?? this.rootUri,
      projectDataPath: projectDataPath ?? this.projectDataPath,
      expandedFolders: expandedFolders ?? Set.from(this.expandedFolders),
      fileExplorerViewMode: fileExplorerViewMode ?? this.fileExplorerViewMode,
      sessionData: sessionData ?? Map.from(this.sessionData),
    );
  }

  // To save project-specific data within its .machine folder
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootUri': rootUri,
        'projectDataPath': projectDataPath,
        'expandedFolders': expandedFolders.toList(),
        'fileExplorerViewMode': fileExplorerViewMode.name,
        'sessionData': sessionData,
      };

  // To load project-specific data from its .machine folder
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      rootUri: json['rootUri'],
      projectDataPath: json['projectDataPath'],
      expandedFolders: Set<String>.from(json['expandedFolders'] ?? []),
      fileExplorerViewMode: FileExplorerViewMode.values.firstWhere(
        (e) => e.name == json['fileExplorerViewMode'],
        orElse: () => FileExplorerViewMode.sortByNameAsc,
      ),
      sessionData: Map<String, dynamic>.from(json['sessionData'] ?? {}),
    );
  }
}

enum FileExplorerViewMode {
  sortByNameAsc,
  sortByNameDesc,
  sortByDateModified,
  showAllFiles,
  showOnlyCode,
}

enum ClipboardOperation {
  cut,
  copy,
}

class ClipboardItem {
  final String uri;
  final bool isFolder;
  final ClipboardOperation operation;

  ClipboardItem({
    required this.uri,
    required this.isFolder,
    required this.operation,
  });
}

// --------------------
// Project Providers
// --------------------

final clipboardProvider = StateProvider<ClipboardItem?>((ref) => null);