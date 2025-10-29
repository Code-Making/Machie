// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_state.dart
// =========================================

import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/commit_iterator.dart';
import 'package:dart_git/utils/file_mode.dart';
import 'package:dart_git/storage/interfaces.dart';

import 'git_provider.dart';
import 'git_object_file.dart';

// NEW: This provider tracks the commit hash that serves as the starting point for the history view.
// When a user "jumps to" a hash, this provider's state is updated.
final gitHistoryStartHashProvider = StateProvider<GitHash?>((ref) => null);

// NEW: A provider to fetch the details of a single commit by its hash.
// This decouples the main commit display from the paginated list.
final gitCommitDetailsProvider = FutureProvider.family<GitCommit?, GitHash>((ref, hash) async {
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  if (gitRepo == null) return null;
  try {
    // Directly read the commit from the object store.
    return await gitRepo.objStorage.readCommit(hash);
  } catch (e) {
    // If the hash is invalid or not a commit, return null.
    return null;
  }
});

// This efficient iterator remains the same.
Stream<GitCommit> firstParentCommitIterator({ required ObjectStorage objStorage, required GitHash from }) async* {
  GitHash? currentHash = from;
  while (currentHash != null) {
    try {
      final commit = await objStorage.readCommit(currentHash);
      yield commit;
      currentHash = commit.parents.isNotEmpty ? commit.parents.first : null;
    } catch (e) { break; }
  }
}

const _commitsPerPage = 10;

class PaginatedCommitsState extends Equatable { /* ... unchanged ... */
  final List<GitCommit> commits;
  final bool isLoading;
  final bool hasMore;
  const PaginatedCommitsState({ this.commits = const [], this.isLoading = true, this.hasMore = true });
  PaginatedCommitsState copyWith({ List<GitCommit>? commits, bool? isLoading, bool? hasMore }) => PaginatedCommitsState(commits: commits ?? this.commits, isLoading: isLoading ?? this.isLoading, hasMore: hasMore ?? this.hasMore);
  @override List<Object?> get props => [commits, isLoading, hasMore];
}

// REFACTORED: This is now an AutoDisposeFamilyAsyncNotifier, parameterized by the starting commit hash.
// When the start hash changes, Riverpod automatically creates a new instance and fetches a new history.
class PaginatedCommitsNotifier extends AutoDisposeFamilyAsyncNotifier<PaginatedCommitsState, GitHash> {
  StreamIterator<GitCommit>? _iterator;

  @override
  Future<PaginatedCommitsState> build(GitHash fromHash) async {
    final gitRepo = await ref.watch(gitRepositoryProvider.future);
    if (gitRepo == null) {
      return const PaginatedCommitsState(isLoading: false, hasMore: false);
    }

    final stream = firstParentCommitIterator(objStorage: gitRepo.objStorage, from: fromHash);
    _iterator = StreamIterator(stream);
    
    return _fetchNextPage(const PaginatedCommitsState(commits: []));
  }

  Future<void> fetchNextPage() async {
    if (state.value?.isLoading ?? true) return;
    if (!(state.value?.hasMore ?? false)) return;
    state = AsyncData(state.value!.copyWith(isLoading: true));
    state = AsyncData(await _fetchNextPage(state.value!));
  }
  
  Future<PaginatedCommitsState> _fetchNextPage(PaginatedCommitsState currentState) async {
    if (_iterator == null) return currentState.copyWith(isLoading: false, hasMore: false);
    final newCommits = <GitCommit>[];
    for (var i = 0; i < _commitsPerPage; i++) {
      if (await _iterator!.moveNext()) {
        newCommits.add(_iterator!.current);
      } else {
        return currentState.copyWith(commits: [...currentState.commits, ...newCommits], isLoading: false, hasMore: false);
      }
    }
    return currentState.copyWith(commits: [...currentState.commits, ...newCommits], isLoading: false, hasMore: true);
  }
}

final paginatedCommitsProvider = AutoDisposeAsyncNotifierProvider.family<PaginatedCommitsNotifier, PaginatedCommitsState, GitHash>(PaginatedCommitsNotifier.new);

// ... (The rest of the file is unchanged) ...
final gitExplorerExpandedFoldersProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

final selectedGitCommitHashProvider = StateProvider<GitHash?>((ref) {
  // We need to know which history we're listening to.
  final startHash = ref.watch(gitHistoryStartHashProvider);
  if (startHash == null) return null;

  // Listen to the specific paginated provider for this history.
  ref.listen(paginatedCommitsProvider(startHash), (_, next) {
    final commits = next.valueOrNull?.commits;
    if (commits != null && commits.isNotEmpty) {
      final currentState = ref.controller.state;
      // Set the initial selected commit only if one isn't already selected.
      if (currentState == null) {
        ref.controller.state = commits.first.hash;
      }
    }
  });
  return null;
});

final gitTreeCacheProvider = AutoDisposeNotifierProvider<GitTreeCacheNotifier, Map<String, AsyncValue<List<GitObjectDocumentFile>>>>(GitTreeCacheNotifier.new);
class GitTreeCacheNotifier extends AutoDisposeNotifier<Map<String, AsyncValue<List<GitObjectDocumentFile>>>> {
  @override
  Map<String, AsyncValue<List<GitObjectDocumentFile>>> build() {
    ref.watch(selectedGitCommitHashProvider);
    return {};
  }
  Future<void> loadDirectory(String pathInRepo) async {
    if (state[pathInRepo] is AsyncLoading || state[pathInRepo] is AsyncData) return;
    state = {...state, pathInRepo: const AsyncLoading()};
    try {
      final gitRepo = await ref.read(gitRepositoryProvider.future);
      final commitHash = ref.read(selectedGitCommitHashProvider);
      if (gitRepo == null || commitHash == null) throw Exception("Git repository or commit not available");
      final commit = await gitRepo.objStorage.readCommit(commitHash);
      GitTree tree;
      if (pathInRepo.isEmpty) { tree = await gitRepo.objStorage.readTree(commit.treeHash); }
      else {
        final rootTree = await gitRepo.objStorage.readTree(commit.treeHash);
        final entry = await gitRepo.objStorage.refSpec(rootTree, pathInRepo);
        tree = await gitRepo.objStorage.readTree(entry.hash);
      }
      final items = tree.entries.map((entry) {
        final fullPath = pathInRepo.isEmpty ? entry.name : '$pathInRepo/${entry.name}';
        return GitObjectDocumentFile(name: entry.name, commitHash: commitHash, objectHash: entry.hash, pathInRepo: fullPath, isDirectory: entry.mode == GitFileMode.Dir);
      }).toList()..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      state = {...state, pathInRepo: AsyncData(items)};
    } catch (e, st) {
      state = {...state, pathInRepo: AsyncError(e, st)};
    }
  }
}