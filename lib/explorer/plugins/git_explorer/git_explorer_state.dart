// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_state.dart
// =========================================

import 'dart:async';
import 'dart:convert'; // For LineSplitter
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/commit_iterator.dart';
import 'package:dart_git/utils/file_mode.dart';

import 'git_provider.dart';
import 'git_object_file.dart';

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

// THE FIX: The gitCommitsProvider is now optimized.
final gitCommitsProvider = FutureProvider<List<GitCommit>>((ref) async {
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  if (gitRepo == null) return [];

  // FAST PATH: Try to read the ref-log first.
  try {
    final commits = await _fetchRecentCommitsFromRefLog(gitRepo, limit: 50);
    if (commits.isNotEmpty) {
      return commits;
    }
  } catch (e) {
    // Log the error but proceed to the fallback.
    print("Could not read ref-log, falling back to graph traversal: $e");
  }

  // SLOW FALLBACK: If the fast path fails, use the original graph traversal.
  final headHash = await gitRepo.headHash();
  final iterator = commitIteratorBFS(objStorage: gitRepo.objStorage, from: headHash);
  return await iterator.take(50).toList();
});

/// Helper function to read recent commit hashes from the ref-log.
Future<List<GitCommit>> _fetchRecentCommitsFromRefLog(GitRepository repo, {int limit = 50}) async {
  final currentBranchName = await repo.currentBranch();
  final refLogPath = 'logs/refs/heads/$currentBranchName';
  final refLogHandle = await repo.gitDirProvider.resolve(repo.gitDir, refLogPath);

  if (!await repo.gitDirProvider.exists(refLogHandle)) {
    return []; // Ref-log file doesn't exist.
  }

  final bytes = await repo.gitDirProvider.read(refLogHandle).expand((b) => b).toList();
  final content = utf8.decode(bytes);

  final lines = LineSplitter.split(content).toList().reversed;
  final hashes = <GitHash>{}; // Use a Set to avoid duplicates
  for (final line in lines) {
    if (hashes.length >= limit) break;
    final parts = line.split(' ');
    if (parts.length > 1) {
      try {
        hashes.add(GitHash(parts[1]));
      } catch (_) {
        // Ignore lines with invalid hashes
      }
    }
  }

  if (hashes.isEmpty) {
    return [];
  }

  // Fetch all commit objects in parallel. This is much faster than sequentially.
  final commitFutures = hashes.map((hash) => repo.objStorage.readCommit(hash)).toList();
  final commits = await Future.wait(commitFutures);

  // Sort the final list by date, as ref-log order isn't strictly commit date order.
  commits.sort((a, b) => b.author.date.compareTo(a.author.date));
  return commits;
}


// ... (gitTreeCacheProvider, GitTreeCacheNotifier, and fileHistoryProvider are unchanged) ...
final gitTreeCacheProvider = AutoDisposeNotifierProvider<GitTreeCacheNotifier, Map<String, AsyncValue<List<GitObjectDocumentFile>>>>(GitTreeCacheNotifier.new);

class GitTreeCacheNotifier extends AutoDisposeNotifier<Map<String, AsyncValue<List<GitObjectDocumentFile>>>> {
  @override
  Map<String, AsyncValue<List<GitObjectDocumentFile>>> build() {
    ref.watch(selectedGitCommitHashProvider);
    return {};
  }
  Future<void> loadDirectory(String pathInRepo) async {
    if (state[pathInRepo] is AsyncLoading || state[pathInRepo] is AsyncData) {
      return;
    }
    state = {...state, pathInRepo: const AsyncLoading()};
    try {
      final gitRepo = await ref.read(gitRepositoryProvider.future);
      final commitHash = ref.read(selectedGitCommitHashProvider);
      if (gitRepo == null || commitHash == null) {
        throw Exception("Git repository or commit not available");
      }
      final commit = await gitRepo.objStorage.readCommit(commitHash);
      GitTree tree;
      if (pathInRepo.isEmpty) {
        tree = await gitRepo.objStorage.readTree(commit.treeHash);
      } else {
        final rootTree = await gitRepo.objStorage.readTree(commit.treeHash);
        final entry = await gitRepo.objStorage.refSpec(rootTree, pathInRepo);
        tree = await gitRepo.objStorage.readTree(entry.hash);
      }
      final items = tree.entries.map((entry) {
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
      state = {...state, pathInRepo: AsyncData(items)};
    } catch (e, st) {
      state = {...state, pathInRepo: AsyncError(e, st)};
    }
  }
}

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