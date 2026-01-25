// FILE: lib/explorer/plugins/git_explorer/git_explorer_state.dart

import 'dart:async';

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/storage/interfaces.dart';
import 'package:dart_git/utils/file_mode.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'git_object_file.dart';
import 'git_provider.dart';

final gitHistoryStartHashProvider = StateProvider<GitHash?>((ref) => null);

final gitCommitDetailsProvider = FutureProvider.family<GitCommit?, GitHash>((
  ref,
  hash,
) async {
  final gitRepo = await ref.watch(gitRepositoryProvider.future);
  if (gitRepo == null) return null;
  try {
    return await gitRepo.objStorage.readCommit(hash);
  } catch (e) {
    return null;
  }
});

Stream<GitCommit> firstParentCommitIterator({
  required ObjectStorage objStorage,
  required GitHash from,
}) async* {
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

const _commitsPerPage = 10;

class PaginatedCommitsState extends Equatable {
  final List<GitCommit> commits;
  final bool isLoading;
  final bool hasMore;
  const PaginatedCommitsState({
    this.commits = const [],
    this.isLoading = true,
    this.hasMore = true,
  });
  PaginatedCommitsState copyWith({
    List<GitCommit>? commits,
    bool? isLoading,
    bool? hasMore,
  }) => PaginatedCommitsState(
    commits: commits ?? this.commits,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
  );
  @override
  List<Object?> get props => [commits, isLoading, hasMore];
}

class PaginatedCommitsNotifier
    extends AutoDisposeFamilyAsyncNotifier<PaginatedCommitsState, GitHash> {
  StreamIterator<GitCommit>? _iterator;

  @override
  Future<PaginatedCommitsState> build(GitHash fromHash) async {
    final gitRepo = await ref.watch(gitRepositoryProvider.future);
    if (gitRepo == null) {
      return const PaginatedCommitsState(isLoading: false, hasMore: false);
    }

    final stream = firstParentCommitIterator(
      objStorage: gitRepo.objStorage,
      from: fromHash,
    );
    _iterator = StreamIterator(stream);

    return _fetchNextPage(const PaginatedCommitsState(commits: []));
  }

  Future<void> fetchNextPage() async {
    if (state.value?.isLoading ?? true) return;
    if (!(state.value?.hasMore ?? false)) return;
    state = AsyncData(state.value!.copyWith(isLoading: true));
    state = AsyncData(await _fetchNextPage(state.value!));
  }

  Future<PaginatedCommitsState> _fetchNextPage(
    PaginatedCommitsState currentState,
  ) async {
    if (_iterator == null) {
      return currentState.copyWith(isLoading: false, hasMore: false);
    }
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

final paginatedCommitsProvider = AutoDisposeAsyncNotifierProvider.family<
  PaginatedCommitsNotifier,
  PaginatedCommitsState,
  GitHash
>(PaginatedCommitsNotifier.new);

// ... (The rest of the file is unchanged) ...
final gitExplorerExpandedFoldersProvider =
    StateProvider.autoDispose<Set<String>>((ref) => {});

// SIMPLIFIED: The selected hash now defaults to whatever the history start hash is.
final selectedGitCommitHashProvider = StateProvider<GitHash?>((ref) {
  return ref.watch(gitHistoryStartHashProvider);
});

final gitTreeCacheProvider = AutoDisposeNotifierProvider<
  GitTreeCacheNotifier,
  Map<String, AsyncValue<List<GitObjectDocumentFile>>>
>(GitTreeCacheNotifier.new);

class GitTreeCacheNotifier
    extends
        AutoDisposeNotifier<
          Map<String, AsyncValue<List<GitObjectDocumentFile>>>
        > {
  @override
  Map<String, AsyncValue<List<GitObjectDocumentFile>>> build() {
    ref.listen<GitHash?>(selectedGitCommitHashProvider, (previous, next) {
      if (previous != next && next != null) {
        state = {};
        ref.read(gitExplorerExpandedFoldersProvider.notifier).state = {};
        loadDirectory('');
      }
    });

    final currentHash = ref.watch(selectedGitCommitHashProvider);
    if (currentHash != null) {
      Future.microtask(() => loadDirectory(''));
    }

    return {};
  }

  Future<void> loadDirectory(String pathInRepo) async {
    // We keep this guard to prevent redundant fetches.
    if (state[pathInRepo] is AsyncLoading || state[pathInRepo] is AsyncData) {
      return;
    }

    final initialCommitHash = ref.read(selectedGitCommitHashProvider);
    if (initialCommitHash == null) return;

    state = {...state, pathInRepo: const AsyncLoading()};

    try {
      final gitRepo = await ref.read(gitRepositoryProvider.future);

      // After an await, re-read the latest state. If the user changed the commit
      // while we were loading the repo, we should abort this load.
      final currentCommitHash = ref.read(selectedGitCommitHashProvider);
      if (gitRepo == null ||
          currentCommitHash == null ||
          currentCommitHash != initialCommitHash) {
        return; // Abort if repo isn't available or commit has changed.
      }

      final commit = await gitRepo.objStorage.readCommit(currentCommitHash);
      GitTree tree;
      if (pathInRepo.isEmpty) {
        tree = await gitRepo.objStorage.readTree(commit.treeHash);
      } else {
        final rootTree = await gitRepo.objStorage.readTree(commit.treeHash);
        final entry = await gitRepo.objStorage.refSpec(rootTree, pathInRepo);
        tree = await gitRepo.objStorage.readTree(entry.hash);
      }
      final items =
          tree.entries.map((entry) {
              final fullPath =
                  pathInRepo.isEmpty ? entry.name : '$pathInRepo/${entry.name}';
              return GitObjectDocumentFile(
                name: entry.name,
                commitHash: currentCommitHash,
                objectHash: entry.hash,
                pathInRepo: fullPath,
                isDirectory: entry.mode == GitFileMode.Dir,
              );
            }).toList()
            ..sort((a, b) {
              if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
              return a.name.compareTo(b.name);
            });

      // Update state only if the provider has not been disposed and the commit hasn't changed.
      if (ref.read(selectedGitCommitHashProvider) == initialCommitHash) {
        state = {...state, pathInRepo: AsyncData(items)};
      }
    } catch (e, st) {
      // If the provider has been disposed, trying to update state will throw.
      // We can safely catch this and do nothing. The check here is mostly for safety.
      if (ref.read(selectedGitCommitHashProvider) == initialCommitHash) {
        state = {...state, pathInRepo: AsyncError(e, st)};
      }
    }
  }
}
