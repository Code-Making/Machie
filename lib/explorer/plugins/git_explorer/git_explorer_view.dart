// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_view.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/dart_git.dart';
import 'package:machine/utils/toast.dart';
// NEW: Import the package for controlling the scroll position.
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../app/app_notifier.dart';
import '../../../project/project_models.dart';
import '../../../widgets/file_list_view.dart' as generic;
import 'git_provider.dart';
import 'git_object_file.dart';
import 'git_explorer_state.dart';

// ... (GitExplorerView and _CurrentCommitDisplay widgets are unchanged) ...
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
    final commitsState = ref.watch(paginatedCommitsProvider);

    final selectedCommit = commitsState.valueOrNull?.commits.firstWhere(
      (c) => c.hash == selectedHash,
      orElse: () => commitsState.valueOrNull?.commits.first ?? GitCommit.create(author: GitAuthor(name: '', email: ''), committer: GitAuthor(name: '', email: ''), message: 'Loading...', treeHash: GitHash.zero(), parents: []),
    );

    if (selectedCommit == null || selectedHash == null) {
      return const SizedBox(height: 64, child: Center(child: LinearProgressIndicator()));
    }

    return ListTile(
      title: Text(
        selectedCommit.message.split('\n').first,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${selectedHash.toOid()} by ${selectedCommit.author.name}',
        style: const TextStyle(fontFamily: 'JetBrainsMono'),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Browse History',
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const _CommitHistorySheet(),
          );
        },
      ),
      isThreeLine: false,
    );
  }
}


// REFACTORED: This widget now correctly handles the initial scroll.
class _CommitHistorySheet extends ConsumerStatefulWidget {
  const _CommitHistorySheet();

  @override
  ConsumerState<_CommitHistorySheet> createState() => _CommitHistorySheetState();
}

class _CommitHistorySheetState extends ConsumerState<_CommitHistorySheet> {
  final _textController = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  
  // THE FIX: State flag to track if the initial scroll has happened.
  bool _didInitialScroll = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
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
    final stateAsync = ref.watch(paginatedCommitsProvider);
    final selectedHash = ref.watch(selectedGitCommitHashProvider);
    
    _itemPositionsListener.itemPositions.addListener(() {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;
      final lastVisible = positions.map((p) => p.index).reduce((max, p) => p > max ? p : max);
      final totalItems = stateAsync.valueOrNull?.commits.length ?? 0;
      if (lastVisible >= totalItems - 5) {
         ref.read(paginatedCommitsProvider.notifier).fetchNextPage();
      }
    });

    // THE FIX: Use ref.listen to reactively perform the initial scroll.
    // This logic runs whenever the paginated data changes.
    ref.listen(paginatedCommitsProvider, (previous, next) {
      // We only act if we haven't scrolled yet AND we have data.
      if (!_didInitialScroll && next is AsyncData<PaginatedCommitsState>) {
        final state = next.value!;
        final index = state.commits.indexWhere((c) => c.hash == selectedHash);

        // If the selected commit is now present in the loaded list...
        if (index != -1) {
          // ...schedule a scroll to it after the frame builds.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_itemScrollController.isAttached) {
              _itemScrollController.jumpTo(index: index, alignment: 0.4);
              // Set the flag so we don't do this ever again for this instance of the sheet.
              _didInitialScroll = true;
            }
          });
        }
      }
    });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.9,
      builder: (_, __) {
        return Scaffold(
          appBar: AppBar(
            primary: false,
            automaticallyImplyLeading: false,
            title: TextField(
              controller: _textController,
              decoration: const InputDecoration(hintText: 'Find commit by hash...'),
              onSubmitted: _submitHash,
              style: const TextStyle(fontFamily: 'JetBrainsMono'),
            ),
            actions: [ IconButton(onPressed: () => _submitHash(_textController.text), icon: const Icon(Icons.search)) ],
          ),
          body: stateAsync.when(
            data: (state) {
              // The scroll logic is now handled by the listener above, not here.
              return ScrollablePositionedList.builder(
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
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text("Error: $e")),
          ),
        );
      },
    );
  }
}

// ... (_GitRecursiveDirectoryView is unchanged) ...
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
            return _GitRecursiveDirectoryView(
              pathInRepo: (directory as GitObjectDocumentFile).pathInRepo,
              depth: depth + 1,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}