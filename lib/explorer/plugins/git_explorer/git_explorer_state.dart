// lib/explorer/plugins/git_explorer/git_explorer_state.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/plumbing/commit_iterator.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/commit.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/diff_commit.dart';
import 'git_provider.dart';
import 'git_object_file.dart';

/// Holds the currently selected commit hash for the Git Explorer view.
final selectedGitCommitHashProvider = StateProvider<GitHash?>((ref) {
  final gitRepo = ref.watch(gitRepositoryProvider);
  return gitRepo?.headHash();
});

/// Fetches the list of commits for the dropdown.
/// For simplicity, this fetches the latest 50 commits.
final gitCommitsProvider = FutureProvider<List<GitCommit>>((ref) async {
  final gitRepo = ref.watch(gitRepositoryProvider);
  if (gitRepo == null) return [];

  final headHash = gitRepo.headHash();
  final iterator = commitIteratorBFS(objStorage: gitRepo.objStorage, from: headHash);
  
  // Take the first 50 commits for the dropdown
  return iterator.take(50).toList();
});

/// A family provider that fetches the tree entries for a given path at a specific commit.
final gitTreeProvider = FutureProvider.family<List<GitObjectDocumentFile>, String>((ref, pathInRepo) async {
  final gitRepo = ref.watch(gitRepositoryProvider);
  final commitHash = ref.watch(selectedGitCommitHashProvider);
  if (gitRepo == null || commitHash == null) return [];

  final commit = gitRepo.objStorage.readCommit(commitHash);
  GitTree tree;
  if (pathInRepo.isEmpty) {
    tree = gitRepo.objStorage.readTree(commit.treeHash);
  } else {
    final entry = gitRepo.objStorage.refSpec(gitRepo.objStorage.readTree(commit.treeHash), pathInRepo);
    tree = gitRepo.objStorage.readTree(entry.hash);
  }

  return tree.entries.map((entry) {
    final fullPath = pathInRepo.isEmpty ? entry.name : '$pathInRepo/${entry.name}';
    return GitObjectDocumentFile(
      name: entry.name,
      commitHash: commitHash,
      objectHash: entry.hash,
      pathInRepo: fullPath,
      isDirectory: entry.mode.isDirectory,
    );
  }).toList()
    ..sort((a, b) { // Basic sort: folders first, then by name
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });
});

/// A family provider that finds the last 5 commits where a specific file was modified.
final fileHistoryProvider = FutureProvider.family<List<GitCommit>, String>((ref, filePath) async {
  final gitRepo = ref.watch(gitRepositoryProvider);
  final headHash = ref.watch(selectedGitCommitHashProvider);
  if (gitRepo == null || headHash == null) return [];

  final history = <GitCommit>[];
  final iterator = commitIteratorBFS(objStorage: gitRepo.objStorage, from: headHash);

  for (final commit in iterator) {
    if (history.length >= 5) break;
    if (commit.parents.isEmpty) continue; // Cannot diff first commit against a parent

    // Diff this commit with its first parent
    final parent = gitRepo.objStorage.readCommit(commit.parents.first);
    final changes = diffCommits(fromCommit: parent, toCommit: commit, objStore: gitRepo.objStorage);
    
    // Check if our file was in the list of modified or added files
    if (changes.merged().any((change) => change.path == filePath)) {
      history.add(commit);
    }
  }

  return history;
});