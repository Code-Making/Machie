// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_state.dart
// =========================================

import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/commit_iterator.dart';
import 'package:dart_git/utils/file_mode.dart';

import 'git_provider.dart';
import 'git_object_file.dart';

// These providers are unchanged and correct for the new design
final gitExplorerExpandedFoldersProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

const _commitsPerPage = 20;

class PaginatedCommitsState extends Equatable {
  final List<GitCommit> commits;
  final bool isLoading;
  final bool hasMore;

  const PaginatedCommitsState({
    this.commits = const [],
    this.isLoading = true,
    this.hasMore = true,
  });

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

class PaginatedCommitsNotifier extends AutoDisposeAsyncNotifier<PaginatedCommitsState> {
  StreamIterator<GitCommit>? _iterator;

  @override
  Future<PaginatedCommitsState> build() async {
    final gitRepo = await ref.watch(gitRepositoryProvider.future);
    if (gitRepo == null) {
      return const PaginatedCommitsState(isLoading: false, hasMore: false);
    }

    final headHash = await gitRepo.headHash();
    final stream = commitIteratorBFS(objStorage: gitRepo.objStorage, from: headHash);
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

final paginatedCommitsProvider = AutoDisposeAsyncNotifierProvider<PaginatedCommitsNotifier, PaginatedCommitsState>(PaginatedCommitsNotifier.new);

final selectedGitCommitHashProvider = StateProvider<GitHash?>((ref) {
  // When the git repository first becomes available, fetch the HEAD hash.
  ref.listen(gitRepositoryProvider, (_, next) {
    if (next is AsyncData && next.value != null) {
      final repo = next.value!;
      repo.headHash().then((hash) {
        if (ref.controller.state == null) {
          ref.controller.state = hash;
        }
      });
    }
  });
  return null; // Start as null, the listener will populate it.
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

// REMOVED: The fileHistoryProvider is no longer needed.