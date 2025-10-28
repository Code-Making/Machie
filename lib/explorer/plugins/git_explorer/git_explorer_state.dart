// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_state.dart
// =========================================

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// THE FIX: Add missing imports from dart_git
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/commit_iterator.dart';
import 'package:dart_git/utils/file_mode.dart';

import 'git_provider.dart';
import 'git_object_file.dart';

/// Holds the currently selected commit hash for the Git Explorer view.
/// It is initialized to null and is populated by a listener when the commits are loaded.
final selectedGitCommitHashProvider = StateProvider<GitHash?>((ref) {
  // When the list of commits is successfully fetched, if no commit has been
  // selected yet, this listener will default to selecting the first one (HEAD).
  ref.listen(gitCommitsProvider, (_, next) {
    if (next.hasValue && next.value!.isNotEmpty) {
      // THE FIX: To avoid a dependency cycle, we access the provider's
      // current state via its controller instead of using ref.read().
      final currentState = ref.controller.state;
      if (currentState == null) {
        ref.controller.state = next.value!.first.hash;
      }
    }
  });

  return null; // Initial state is null until the listener populates it.
});

/// Fetches the list of the first 50 commits for the current branch.
final gitCommitsProvider = FutureProvider<List<GitCommit>>((ref) async {
  // Await the result of the repository provider.
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  if (gitRepo == null) return [];

  // All API calls are now asynchronous.
  final headHash = await gitRepo.headHash();
  final iterator = commitIteratorBFS(objStorage: gitRepo.objStorage, from: headHash);
  
  // The stream from the iterator must be awaited.
  return await iterator.take(50).toList();
});

/// A family provider that fetches the tree entries for a given path at a specific commit.
final gitTreeProvider = FutureProvider.family<List<GitObjectDocumentFile>, String>((ref, pathInRepo) async {
  // Await the repository and watch the selected commit hash.
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  final commitHash = ref.watch(selectedGitCommitHashProvider);

  // If dependencies aren't ready, return an empty list.
  if (gitRepo == null || commitHash == null) return [];

  // All object storage operations are now async.
  final commit = await gitRepo.objStorage.readCommit(commitHash);
  GitTree tree;
  if (pathInRepo.isEmpty) {
    tree = await gitRepo.objStorage.readTree(commit.treeHash);
  } else {
    // We need to await the tree read before passing it to refSpec
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

/// A family provider that finds the last 5 commits where a specific file was modified.
final fileHistoryProvider = FutureProvider.family<List<GitCommit>, String>((ref, filePath) async {
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  // Watch, don't await, the selected hash provider as it's synchronous state.
  final headHash = ref.watch(selectedGitCommitHashProvider);

  if (gitRepo == null || headHash == null) return [];

  final history = <GitCommit>[];
  final iterator = commitIteratorBFS(objStorage: gitRepo.objStorage, from: headHash);

  // Use 'await for' to iterate over the async stream from the iterator.
  await for (final commit in iterator) {
    if (history.length >= 5) break;
    if (commit.parents.isEmpty) continue;

    // All API calls are now async.
    final parent = await gitRepo.objStorage.readCommit(commit.parents.first);
    final changes = await diffCommits(fromCommit: parent, toCommit: commit, objStore: gitRepo.objStorage);
    
    if (changes.merged().any((change) => change.path == filePath)) {
      history.add(commit);
    }
  }

  return history;
});