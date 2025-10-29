// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_state.dart
// =========================================

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/commit_iterator.dart';
import 'package:dart_git/utils/file_mode.dart';

import 'git_provider.dart';
import 'git_object_file.dart';

// REPLACED: The single path provider is gone.
// NEW: A provider to hold the set of expanded folder paths for the tree view.
final gitExplorerExpandedFoldersProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

final selectedGitCommitHashProvider = StateProvider<GitHash?>((ref) {
  ref.listen(gitCommitsProvider, (_, next) {
    if (next.hasValue && next.value!.isNotEmpty) {
      final currentState = ref.controller.state;
      if (currentState == null) {
        ref.controller.state = next.value!.first.hash;
      }
    }
  });

  return null;
});

final gitCommitsProvider = FutureProvider<List<GitCommit>>((ref) async {
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  if (gitRepo == null) return [];

  final headHash = await gitRepo.headHash();
  final iterator = commitIteratorBFS(objStorage: gitRepo.objStorage, from: headHash);
  
  return await iterator.take(50).toList();
});

final gitTreeProvider = FutureProvider.family<List<GitObjectDocumentFile>, String>((ref, pathInRepo) async {
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  final commitHash = ref.watch(selectedGitCommitHashProvider);

  if (gitRepo == null || commitHash == null) return [];

  final commit = await gitRepo.objStorage.readCommit(commitHash);
  GitTree tree;
  if (pathInRepo.isEmpty) {
    tree = await gitRepo.objStorage.readTree(commit.treeHash);
  } else {
    final rootTree = await gitRepo.objStorage.readTree(commit.treeHash);
    final entry = await gitRepo.objStorage.refSpec(rootTree, pathInRepo);
    tree = await gitRepo.objStorage.readTree(entry.hash);
  }

  return tree.entries.map((entry) {
    final fullPath = pathInRepo.isEmpty ? entry.name : '$pathInRepo/${entry.name}';
    return GitObjectDocumentFile(
      name: entry.name,
      commitHash: commitHash,
      objectHash: entry.hash,
      pathInRepo: fullPath,
      isDirectory: entry.mode == GitFileMode.Dir,
    );
  }).toList()
    ..sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });
});

final fileHistoryProvider = FutureProvider.family<List<GitCommit>, String>((ref, filePath) async {
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  final headHash = ref.watch(selectedGitCommitHashProvider);

  if (gitRepo == null || headHash == null) return [];

  final history = <GitCommit>[];
  final iterator = commitIteratorBFS(objStorage: gitRepo.objStorage, from: headHash);

  await for (final commit in iterator) {
    if (history.length >= 5) break;
    if (commit.parents.isEmpty) continue;

    final parent = await gitRepo.objStorage.readCommit(commit.parents.first);
    final changes = await diffCommits(fromCommit: parent, toCommit: commit, objStore: gitRepo.objStorage);
    
    if (changes.merged().any((change) => change.path == filePath)) {
      history.add(commit);
    }
  }

  return history;
});