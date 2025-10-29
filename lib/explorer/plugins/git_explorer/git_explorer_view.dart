// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_view.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/dart_git.dart';
import 'package:machine/utils/toast.dart';

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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ref.read(gitTreeCacheProvider.notifier).loadDirectory('');
          }
        });
        
        // REFACTORED: The main view now contains the new commit browser.
        return const Column(
          children: [
            _CommitBrowser(),
            Divider(height: 1),
            Expanded(child: _GitRecursiveDirectoryView(pathInRepo: '')),
          ],
        );
      },
    );
  }
}

// REWRITTEN: This widget replaces _CommitSelector.
class _CommitBrowser extends ConsumerStatefulWidget {
  const _CommitBrowser();

  @override
  ConsumerState<_CommitBrowser> createState() => _CommitBrowserState();
}

class _CommitBrowserState extends ConsumerState<_CommitBrowser> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();

    // Sync the text field when the selected hash changes from outside
    ref.listenManual(selectedGitCommitHashProvider, (prev, next) {
      if (next != null && _controller.text != next.toString()) {
        _controller.text = next.toString();
      }
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitHash(String text) {
    try {
      final hash = GitHash(text);
      ref.read(selectedGitCommitHashProvider.notifier).state = hash;
      FocusScope.of(context).unfocus(); // Dismiss keyboard
    } catch (e) {
      MachineToast.error("Invalid Git hash format");
    }
  }

  @override
  Widget build(BuildContext context) {
    // One-time read to initialize the text field with the first available hash
    ref.listenOnce(selectedGitCommitHashProvider, (prev, next) {
      if (next != null) {
        _controller.text = next.toString();
      }
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Commit Hash',
                isDense: true,
                hintText: 'Enter a commit hash...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: _submitHash,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Browse History',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const _CommitHistorySheet(),
              );
            },
          )
        ],
      ),
    );
  }
}

// NEW: A widget for the paginated history modal sheet.
class _CommitHistorySheet extends ConsumerStatefulWidget {
  const _CommitHistorySheet();

  @override
  ConsumerState<_CommitHistorySheet> createState() => _CommitHistorySheetState();
}

class _CommitHistorySheetState extends ConsumerState<_CommitHistorySheet> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      // User is near the bottom, fetch the next page.
      ref.read(paginatedCommitsProvider.notifier).fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(paginatedCommitsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.9,
      builder: (_, controller) {
        // We use the passed controller to make the sheet scrollable.
        _scrollController.hasClients; // Ensure it's attached.
        
        return stateAsync.when(
          data: (state) {
            return ListView.builder(
              controller: _scrollController,
              itemCount: state.commits.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == state.commits.length) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ));
                }

                final commit = state.commits[index];
                return ListTile(
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
        );
      },
    );
  }
}


// REFACTORED WIDGET: Long-press functionality removed.
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
          // REMOVED: The itemBuilder and InkWell for long-press are gone.
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}