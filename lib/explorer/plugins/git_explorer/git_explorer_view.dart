// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_view.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/dart_git.dart';
import 'package:machine/utils/toast.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../app/app_notifier.dart';
import '../../../project/project_models.dart';
import '../../../widgets/file_list_view.dart' as generic;
import 'git_provider.dart';
import 'git_object_file.dart';
import 'git_explorer_state.dart';

class GitExplorerView extends ConsumerWidget {
  final Project project;
  const GitExplorerView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(selectedGitCommitHashProvider, (_, __) {
      ref.read(gitExplorerExpandedFoldersProvider.notifier).state = {};
    });

    final gitRepoAsync = ref.watch(gitRepositoryProvider);

    return gitRepoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading Git repository:\n$err')),
      data: (gitRepo) {
        if (gitRepo == null) {
          return const Center(child: Text('This project is not a Git repository.'));
        }

        // Set the initial selected commit hash from HEAD.
        // This only runs once when the repo is first loaded.
        if (ref.read(selectedGitCommitHashProvider) == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            ref.read(selectedGitCommitHashProvider.notifier).state = await gitRepo.headHash();
          });
        }
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ref.read(gitTreeCacheProvider.notifier).loadDirectory('');
          }
        });
        
        return const Column(
          children: [
            _CurrentCommitDisplay(),
            Divider(height: 1),
            Expanded(child: _GitRecursiveDirectoryView(pathInRepo: '')),
          ],
        );
      },
    );
  }
}

class _CurrentCommitDisplay extends ConsumerWidget {
  const _CurrentCommitDisplay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedHash = ref.watch(selectedGitCommitHashProvider);
    if (selectedHash == null) {
      return const SizedBox(height: 64, child: Center(child: LinearProgressIndicator()));
    }
    
    // Instead of relying on the paginated list, we fetch the specific commit object.
    // Riverpod's caching makes this efficient.
    final commitFuture = ref.watch(gitRepositoryProvider).whenData(
      (repo) => repo?.objStorage.readCommit(selectedHash)
    );

    return commitFuture.when(
      data: (commit) {
        if (commit == null) return const SizedBox(height: 64);
        return ListTile(
          title: Text(commit.message.split('\n').first, overflow: TextOverflow.ellipsis),
          subtitle: Text('${selectedHash.toOid()} by ${commit.author.name}', style: const TextStyle(fontFamily: 'JetBrainsMono')),
          trailing: IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Browse History',
            onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const _CommitHistorySheet()),
          ),
        );
      },
      loading: () => const SizedBox(height: 64, child: Center(child: LinearProgressIndicator())),
      error: (e, st) => ListTile(title: Text('Error loading commit ${selectedHash.toOid()}'), subtitle: Text('$e')),
    );
  }
}


class _CommitHistorySheet extends ConsumerStatefulWidget {
  const _CommitHistorySheet();

  @override
  ConsumerState<_CommitHistorySheet> createState() => _CommitHistorySheetState();
}

class _CommitHistorySheetState extends ConsumerState<_CommitHistorySheet> {
  final _textController = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_onScroll);
  }
  
  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    _textController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    
    final lastVisible = positions.map((p) => p.index).reduce((max, p) => p > max ? p : max);
    final totalItems = ref.read(commitHistoryProvider).valueOrNull?.commits.length ?? 0;
    
    if (totalItems > 0 && lastVisible >= totalItems - 5) {
      ref.read(commitHistoryProvider.notifier).fetchNextPage();
    }
  }
  
  void _submitHash(String text) {
    if (text.trim().isEmpty) return;
    try {
      final hash = GitHash(text.trim());
      ref.read(selectedGitCommitHashProvider.notifier).state = hash;
      Navigator.pop(context);
    } catch (e) {
      MachineToast.error("Invalid or unknown Git hash");
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(commitHistoryProvider);
    final selectedHash = ref.watch(selectedGitCommitHashProvider);

    // This listener declaratively handles the one-time scroll.
    ref.listen(commitHistoryProvider, (_, next) {
      final state = next.valueOrNull;
      if (state == null) return;

      if (state.initialScrollIndex != null && !state.initialScrollCompleted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_itemScrollController.isAttached) {
            _itemScrollController.jumpTo(index: state.initialScrollIndex!, alignment: 0.4);
            // Tell the notifier that the scroll is done.
            ref.read(commitHistoryProvider.notifier).completeInitialScroll();
          }
        });
      }
    });

    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.8, maxChildSize: 0.9,
      builder: (_, __) => Scaffold(
        appBar: AppBar(
          primary: false, automaticallyImplyLeading: false,
          title: TextField(controller: _textController, decoration: const InputDecoration(hintText: 'Find commit by hash...'), onSubmitted: _submitHash, style: const TextStyle(fontFamily: 'JetBrainsMono')),
          actions: [IconButton(onPressed: () => _submitHash(_textController.text), icon: const Icon(Icons.search))],
        ),
        body: stateAsync.when(
          data: (state) => ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            itemCount: state.commits.length + (state.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == state.commits.length) {
                return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
              }
              final commit = state.commits[index];
              final isSelected = commit.hash == selectedHash;
              return ListTile(
                selected: isSelected,
                selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                title: Text(commit.message.split('\n').first),
                subtitle: Text('${commit.hash.toOid()} by ${commit.author.name}'),
                onTap: () {
                  ref.read(selectedGitCommitHashProvider.notifier).state = commit.hash;
                  Navigator.pop(context);
                },
              );
            },
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text("Error: $e")),
        ),
      ),
    );
  }
}

// _GitRecursiveDirectoryView is now correct and unchanged.
class _GitRecursiveDirectoryView extends ConsumerWidget {
  final String pathInRepo;
  final int depth;

  const _GitRecursiveDirectoryView({required this.pathInRepo, this.depth = 1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoryState = ref.watch(gitTreeCacheProvider)[pathInRepo];
    final expandedPaths = ref.watch(gitExplorerExpandedFoldersProvider);

    if (directoryState == null) return const Center(child: CircularProgressIndicator());

    return directoryState.when(
      data: (items) => generic.FileListView(
        items: items,
        expandedDirectoryUris: expandedPaths,
        depth: depth,
        onFileTapped: (file) async {
          final navigator = Navigator.of(context);
          final success = await ref.read(appNotifierProvider.notifier).openFileInEditor(file);
          if (success && context.mounted) navigator.pop();
        },
        onExpansionChanged: (directory, isExpanded) {
          final path = (directory as GitObjectDocumentFile).pathInRepo;
          final notifier = ref.read(gitExplorerExpandedFoldersProvider.notifier);
          if (isExpanded) {
            ref.read(gitTreeCacheProvider.notifier).loadDirectory(path);
            notifier.update((state) => {...state, path});
          } else {
            notifier.update((state) => state..remove(path));
          }
        },
        directoryChildrenBuilder: (directory) => _GitRecursiveDirectoryView(
          pathInRepo: (directory as GitObjectDocumentFile).pathInRepo,
          depth: depth + 1,
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}