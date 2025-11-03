// lib/explorer/plugins/git_explorer/git_object_file.dart

import 'package:flutter/foundation.dart';

import 'package:dart_git/plumbing/git_hash.dart';

import '../../../data/file_handler/file_handler.dart';

/// A virtual DocumentFile that represents a file (blob) inside the Git object database
/// at a specific commit.
@immutable
class GitObjectDocumentFile implements DocumentFile {
  @override
  final String name;

  @override
  final String uri; // A virtual URI, e.g., "git://<commitHash>/<path>"

  @override
  final bool isDirectory;

  final GitHash commitHash;
  final GitHash objectHash;
  final String pathInRepo;

  GitObjectDocumentFile({
    required this.name,
    required this.commitHash,
    required this.objectHash,
    required this.pathInRepo,
    this.isDirectory = false,
  }) : uri = 'git://${commitHash.toString()}/$pathInRepo';

  // These are mostly placeholders as it's a virtual read-only file
  @override
  int get size => 0;

  @override
  DateTime get modifiedDate => DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get mimeType => 'application/octet-stream';
}
