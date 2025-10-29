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

// This provider tracks the commit hash that serves as the starting point for the history view.
// It's updated when the user "jumps to" a specific hash.
final gitHistoryStartHashProvider = StateProvider<GitHash?>((ref) => null);

// A provider to fetch the details of a single commit, used by the main display.
final gitCommitDetailsProvider = FutureProvider.family<GitCommit?, GitHash>((ref, hash) async {
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  if (gitRepo == null) return null;
  try {
    return await gitRepo.objStorage.readCommit(hash);
  } catch (e) {
    return null;
  }
});


Stream<GitCommit> firstParentCommitIterator({ required ObjectStorage objStorage, required GitHash from }) async* {
  GitHash? currentHash = from;
  while (currentHash != null) {
    try {
      final commit = await objStorage.readCommit(currentHash);
      yield commit;
      currentHash = commit.parents.isNotEmpty ? commit.parents.first : null;
    } catch (e) {
      break;
    }
  }
}

const _commitsPerPage = 20;

class PaginatedCommitsState extends Equatable {
  final List<GitCommit> commits;
  final bool isLoading;
  final bool hasMore;
  const PaginatedCommitsState({ this.commits = const [], this.isLoading = true, this.hasMore = true });
  PaginatedCommitsState copyWith({ List<GitCommit>? commits, bool? isLoading, bool? hasMore }) {
    return PaginatedCommitsState(
      commits: commits ?? this.commits,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
    );
  }
  @override
  List<Object?> get props => [commits, isLoading, hasMore];
}

// REFACTORED to a FamilyAsyncNotifier, parameterized by the starting commit hash.
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
        return currentState.copyWith(
          commits: [...currentState.commits, ...newCommits],
          isLoading: false,
          hasMore: false,
        );
      }
    }
    return currentState.copyWith(
      commits: [...currentState.commits, ...newCommits],
      isLoading: false,
      hasMore: true,
    );
  }
}

final paginatedCommitsProvider = AutoDisposeAsyncNotifierProvider.family<PaginatedCommitsNotifier, PaginatedCommitsState, GitHash>(PaginatedCommitsNotifier.new);

// ... The rest of the file (selectedGitCommitHashProvider, etc.) is unchanged ...
final gitExplorerExpandedFoldersProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

final selectedGitCommitHashProvider = StateProvider<GitHash?>((ref) {
  final startHash = ref.watch(gitHistoryStartHashProvider);
  if (startHash == null) return null;

  ref.listen(paginatedCommitsProvider(startHash), (_, next) {
    final commits = next.valueOrNull?.commits;
    if (commits != null && commits.isNotEmpty) {
      final currentState = ref.controller.state;
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