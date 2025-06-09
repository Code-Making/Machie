// lib/project/project_models.dart

import 'package:flutter/material.dart'; // For IconData

// The old Project class has been removed and replaced by the
// Project interface and LocalFileSystemProject implementation.

class ProjectMetadata {
  final String id;
  final String name;
  final String rootUri;
  final DateTime lastOpenedDateTime;
  
  // These are no longer needed here, as the session is part of the project's own data
  // final int? lastOpenedTabIndex;
  // final String? lastOpenedFileUri;

  ProjectMetadata({
    required this.id,
    required this.name,
    required this.rootUri,
    required this.lastOpenedDateTime,
  });

  ProjectMetadata copyWith({
    String? id,
    String? name,
    String? rootUri,
    DateTime? lastOpenedDateTime,
  }) {
    return ProjectMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      rootUri: rootUri ?? this.rootUri,
      lastOpenedDateTime: lastOpenedDateTime ?? this.lastOpenedDateTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootUri': rootUri,
        'lastOpenedDateTime': lastOpenedDateTime.toIso8601String(),
      };

  factory ProjectMetadata.fromJson(Map<String, dynamic> json) {
    return ProjectMetadata(
      id: json['id'],
      name: json['name'],
      rootUri: json['rootUri'],
      lastOpenedDateTime: DateTime.parse(json['lastOpenedDateTime']),
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