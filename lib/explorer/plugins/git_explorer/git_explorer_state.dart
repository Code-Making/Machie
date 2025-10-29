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

// === START: NEW COMMIT HISTORY NOTIFIER ===

const _commitsPerPage = 30;

// The state class now holds all UI-relevant information for the history sheet.
class CommitHistoryState extends Equatable {
  final List<GitCommit> commits;
  final bool hasMore;
  final bool isLoadingMore;
  final int? initialScrollIndex; // The index to scroll to on first load.
  final bool initialScrollCompleted; // Flag to prevent re-scrolling.

  const CommitHistoryState({
    this.commits = const [],
    this.hasMore = true,
    this.isLoadingMore = false,
    this.initialScrollIndex,
    this.initialScrollCompleted = false,
  });

  CommitHistoryState copyWith({
    List<GitCommit>? commits,
    bool? hasMore,
    bool? isLoadingMore,
    int? initialScrollIndex,
    bool? initialScrollCompleted,
  }) {
    return CommitHistoryState(
      commits: commits ?? this.commits,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      initialScrollIndex: initialScrollIndex ?? this.initialScrollIndex,
      initialScrollCompleted: initialScrollCompleted ?? this.initialScrollCompleted,
    );
  }

  @override
  List<Object?> get props => [commits, hasMore, isLoadingMore, initialScrollIndex, initialScrollCompleted];
}

// The new AsyncNotifier to manage the history sheet's state.
class CommitHistoryNotifier extends AutoDisposeAsyncNotifier<CommitHistoryState> {
  StreamIterator<GitCommit>? _iterator;

  @override
  Future<CommitHistoryState> build() async {
    final gitRepo = await ref.watch(gitRepositoryProvider.future);
    if (gitRepo == null) {
      return const CommitHistoryState(hasMore: false);
    }

    final headHash = await gitRepo.headHash();
    final stream = commitIteratorBFS(objStorage: gitRepo.objStorage, from: headHash);
    _iterator = StreamIterator(stream);

    final firstPage = await _fetchPage();
    
    // Find the index of the currently selected commit to enable the initial scroll.
    final selectedHash = ref.read(selectedGitCommitHashProvider);
    int? scrollIndex;
    if (selectedHash != null) {
      scrollIndex = firstPage.indexWhere((c) => c.hash == selectedHash);
      if (scrollIndex == -1) scrollIndex = null;
    }
    
    return CommitHistoryState(
      commits: firstPage,
      hasMore: firstPage.length == _commitsPerPage,
      initialScrollIndex: scrollIndex,
    );
  }

  Future<void> fetchNextPage() async {
    if (state.value?.isLoadingMore ?? true) return;
    if (!(state.value?.hasMore ?? false)) return;

    state = AsyncData(state.value!.copyWith(isLoadingMore: true));
    
    final newCommits = await _fetchPage();
    final currentState = state.value!;

    state = AsyncData(currentState.copyWith(
      commits: [...currentState.commits, ...newCommits],
      hasMore: newCommits.length == _commitsPerPage,
      isLoadingMore: false,
    ));
  }

  Future<List<GitCommit>> _fetchPage() async {
    if (_iterator == null) return [];
    
    final pageCommits = <GitCommit>[];
    for (var i = 0; i < _commitsPerPage; i++) {
      if (await _iterator!.moveNext()) {
        pageCommits.add(_iterator!.current);
      } else {
        break;
      }
    }
    return pageCommits;
  }
  
  // Method for the UI to call after it has performed the initial scroll.
  void completeInitialScroll() {
    if (state.value?.initialScrollCompleted == false) {
      state = AsyncData(state.value!.copyWith(initialScrollCompleted: true));
    }
  }
}

final commitHistoryProvider = AutoDisposeAsyncNotifierProvider<CommitHistoryNotifier, CommitHistoryState>(CommitHistoryNotifier.new);

// === END: NEW COMMIT HISTORY NOTIFIER ===


// The old paginated provider is removed.
// The selectedGitCommitHashProvider is now simplified.
final selectedGitCommitHashProvider = StateProvider<GitHash?>((ref) => null);

final selectedCommitProvider = FutureProvider.autoDispose<GitCommit?>((ref) async {
  final repo = await ref.watch(gitRepositoryProvider.future);
  final selectedHash = ref.watch(selectedGitCommitHashProvider);

  if (repo == null || selectedHash == null) {
    return null;
  }

  // This provider now correctly handles the full async chain.
  return repo.objStorage.readCommit(selectedHash);
});

// These providers remain unchanged.
final gitExplorerExpandedFoldersProvider = StateProvider.autoDispose<Set<String>>((ref) => {});
final gitTreeCacheProvider = AutoDisposeNotifierProvider<GitTreeCacheNotifier, Map<String, AsyncValue<List<GitObjectDocumentFile>>>>(GitTreeCacheNotifier.new);
class GitTreeCacheNotifier extends AutoDisposeNotifier<Map<String, AsyncValue<List<GitObjectDocumentFile>>>> {
  @override
  Map<String, AsyncValue<List<GitObjectDocumentFile>>> build() {
    ref.watch(selectedGitCommitHashProvider); return {};
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