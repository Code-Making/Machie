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

        // Initialize the starting hash for the history view to HEAD.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (context.mounted && ref.read(gitHistoryStartHashProvider) == null) {
            final headHash = await gitRepo.headHash();
            ref.read(gitHistoryStartHashProvider.notifier).state = headHash;
          }
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

// REFACTORED: This widget now fetches its own details using a dedicated provider.
class _CurrentCommitDisplay extends ConsumerWidget {
  const _CurrentCommitDisplay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedHash = ref.watch(selectedGitCommitHashProvider);
    if (selectedHash == null) {
      return const SizedBox(height: 64, child: Center(child: LinearProgressIndicator()));
    }
    
    // Watch the new provider to get details for the selected commit
    final commitDetailsAsync = ref.watch(gitCommitDetailsProvider(selectedHash));

    return commitDetailsAsync.when(
      data: (selectedCommit) {
        if (selectedCommit == null) {
          return ListTile(
            title: const Text('Commit not found', style: TextStyle(color: Colors.red)),
            subtitle: Text(selectedHash.toString(), style: const TextStyle(fontFamily: 'JetBrainsMono')),
            trailing: _buildHistoryButton(context),
          );
        }
        return ListTile(
          title: Text(selectedCommit.message.split('\n').first, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${selectedHash.toOid()} by ${selectedCommit.author.name}', style: const TextStyle(fontFamily: 'JetBrainsMono')),
          trailing: _buildHistoryButton(context),
          isThreeLine: false,
        );
      },
      loading: () => const SizedBox(height: 64, child: Center(child: LinearProgressIndicator())),
      error: (e, st) => ListTile(title: Text('Error: $e')),
    );
  }

  Widget _buildHistoryButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.history),
      tooltip: 'Browse History',
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _CommitHistorySheet(),
        );
      },
    );
  }
}

// REWRITTEN WIDGET: Logic for submitting hash is much more robust.
class _CommitHistorySheet extends ConsumerStatefulWidget {
  const _CommitHistorySheet();
  @override
  ConsumerState<_CommitHistorySheet> createState() => _CommitHistorySheetState();
}

class _CommitHistorySheetState extends ConsumerState<_CommitHistorySheet> {
  final _textController = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  bool _didInitialScroll = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submitHash(String text) async {
    if (text.trim().isEmpty) return;
    final navigator = Navigator.of(context); // Capture navigator before async gap

    try {
      final hash = GitHash(text.trim());
      // Verify the commit exists before we change the state
      final gitRepo = await ref.read(gitRepositoryProvider.future);
      await gitRepo?.objStorage.readCommit(hash);

      // It's a valid commit, so update both providers to "jump" the history view
      ref.read(gitHistoryStartHashProvider.notifier).state = hash;
      ref.read(selectedGitCommitHashProvider.notifier).state = hash;
      navigator.pop();
    } catch (e) {
      MachineToast.error("Invalid or unknown Git commit hash");
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final startHash = ref.watch(gitHistoryStartHashProvider);
    if (startHash == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final stateAsync = ref.watch(paginatedCommitsProvider(startHash));
    final selectedHash = ref.watch(selectedGitCommitHashProvider);
    
    _itemPositionsListener.itemPositions.addListener(() {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;
      final lastVisible = positions.map((p) => p.index).reduce((max, p) => p > max ? p : max);
      final totalItems = stateAsync.valueOrNull?.commits.length ?? 0;
      if (lastVisible >= totalItems - 5) {
         ref.read(paginatedCommitsProvider(startHash).notifier).fetchNextPage();
      }
    });

    ref.listen(paginatedCommitsProvider(startHash), (previous, next) {
      if (!_didInitialScroll && next is AsyncData<PaginatedCommitsState>) {
        final state = next.value!;
        final index = state.commits.indexWhere((c) => c.hash == selectedHash);
        if (index != -1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_itemScrollController.isAttached) {
              _itemScrollController.jumpTo(index: index, alignment: 0.4);
              _didInitialScroll = true;
            }
          });
        }
      }
    });

    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.8, maxChildSize: 0.9,
      builder: (_, __) => Scaffold(
        appBar: AppBar(
          primary: false, automaticallyImplyLeading: false,
          title: TextField(controller: _textController, decoration: const InputDecoration(hintText: 'Find commit by hash...'), onSubmitted: _submitHash, style: const TextStyle(fontFamily: 'JetBrainsMono')),
          actions: [ IconButton(onPressed: () => _submitHash(_textController.text), icon: const Icon(Icons.search)) ],
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


// _GitRecursiveDirectoryView is unchanged
class _GitRecursiveDirectoryView extends ConsumerWidget {
  final String pathInRepo;
  final int depth;
  const _GitRecursiveDirectoryView({required this.pathInRepo, this.depth = 1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoryState = ref.watch(gitTreeCacheProvider)[pathInRepo];
    final expandedPaths = ref.watch(gitExplorerExpandedFoldersProvider);
    if (directoryState == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return directoryState.when(
      data: (items) {
        return generic.FileListView(
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
          directoryChildrenBuilder: (directory) {
            return _GitRecursiveDirectoryView(pathInRepo: (directory as GitObjectDocumentFile).pathInRepo, depth: depth + 1);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}