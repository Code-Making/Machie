// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_view.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/dart_git.dart';

import '../../../app/app_notifier.dart';
import '../../../project/project_models.dart';
import '../../../widgets/file_list_view.dart' as generic; // Keep for FileTypeIcon
import 'git_provider.dart';
import 'git_object_file.dart';
import 'git_explorer_state.dart';

class GitExplorerView extends ConsumerWidget {
  final Project project;
  const GitExplorerView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for commit changes to reset the path back to root
    ref.listen(selectedGitCommitHashProvider, (_, __) {
      ref.read(gitExplorerPathProvider.notifier).state = '';
    });

    final gitRepoAsync = ref.watch(gitRepositoryProvider);

    return gitRepoAsync.when(
      loading: () => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning for Git repository...'),
          ],
        ),
      ),
      error: (err, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Error loading Git repository:\n$err', textAlign: TextAlign.center),
        ),
      ),
      data: (gitRepo) {
        if (gitRepo == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'This project is not a Git repository.',
                textAlign: TextAlign.center,
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          );
        }

        return const Column(
          children: [
            _CommitSelector(),
            Divider(height: 1),
            // NEW: Path navigator bar
            _GitPathNavigator(),
            Divider(height: 1),
            Expanded(child: _GitDirectoryView()),
          ],
        );
      },
    );
  }
}

// NEW WIDGET: A bar to show the current path and allow navigating up.
class _GitPathNavigator extends ConsumerWidget {
  const _GitPathNavigator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(gitExplorerPathProvider);
    final pathNotifier = ref.read(gitExplorerPathProvider.notifier);

    return Container(
      height: 40,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            iconSize: 20,
            tooltip: 'Up one level',
            onPressed: path.isEmpty
                ? null
                : () {
                    final lastSlash = path.lastIndexOf('/');
                    if (lastSlash == -1) {
                      pathNotifier.state = '';
                    } else {
                      pathNotifier.state = path.substring(0, lastSlash);
                    }
                  },
          ),
          Expanded(
            child: Text(
              path.isEmpty ? '/' : '/$path',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}


// ... (_CommitSelector remains the same) ...
class _CommitSelector extends ConsumerWidget {
  const _CommitSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commitsAsync = ref.watch(gitCommitsProvider);
    final selectedHash = ref.watch(selectedGitCommitHashProvider);

    return commitsAsync.when(
      data: (commits) {
        if (commits.isEmpty) {
          return const ListTile(title: Text('No commits found in this repository.'));
        }

        // Handle the case where selectedHash might still be null briefly
        if (selectedHash == null) {
          return const SizedBox(height: 56, child: Center(child: LinearProgressIndicator()));
        }

        final selectedCommit = commits.firstWhere((c) => c.hash == selectedHash, orElse: () => commits.first);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<GitHash>(
              value: selectedCommit.hash,
              onChanged: (newHash) {
                if (newHash != null) {
                  ref.read(selectedGitCommitHashProvider.notifier).state = newHash;
                }
              },
              isExpanded: true,
              itemHeight: 60, // Give more space for two lines of text
              items: commits.map((commit) {
                return DropdownMenuItem(
                  value: commit.hash,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        commit.message.split('\n').first,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${commit.hash.toOid()} by ${commit.author.name}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'JetBrainsMono'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 56, child: Center(child: LinearProgressIndicator())),
      error: (err, st) => ListTile(title: Text('Error loading commits: $err')),
    );
  }
}

// REFACTORED WIDGET: Now builds a simple list and handles navigation taps.
class _GitDirectoryView extends ConsumerWidget {
  const _GitDirectoryView();

  void _showFileHistoryMenu(BuildContext context, WidgetRef ref, GitObjectDocumentFile file) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Consumer(builder: (context, ref, _) {
        final historyAsync = ref.watch(fileHistoryProvider(file.pathInRepo));
        return historyAsync.when(
          data: (commits) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Recent Changes to ${file.name}', style: Theme.of(context).textTheme.titleLarge),
              ),
              const Divider(height: 1),
              if (commits.isEmpty) const ListTile(title: Text('No recent changes found in this branch.')),
              ...commits.map((commit) => ListTile(
                    title: Text(commit.message.split('\n').first, overflow: TextOverflow.ellipsis),
                    subtitle: Text(commit.hash.toOid(), style: const TextStyle(fontFamily: 'JetBrainsMono')),
                    onTap: () {
                      ref.read(selectedGitCommitHashProvider.notifier).state = commit.hash;
                      Navigator.pop(ctx);
                    },
                  )),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ListTile(title: Text('Error: $e')),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read the current path from the new provider
    final pathInRepo = ref.watch(gitExplorerPathProvider);
    final treeAsync = ref.watch(gitTreeProvider(pathInRepo));

    return treeAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('This directory is empty.'));
        }

        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];

            final tile = ListTile(
              dense: true,
              leading: generic.FileTypeIcon(file: item),
              title: Text(item.name),
              onTap: () async {
                if (item.isDirectory) {
                  // On directory tap, update the path provider to navigate "in"
                  ref.read(gitExplorerPathProvider.notifier).state = item.pathInRepo;
                } else {
                  // On file tap, open it in the editor and close the drawer
                  final navigator = Navigator.of(context);
                  final success = await ref.read(appNotifierProvider.notifier).openFileInEditor(item);
                  if (success && context.mounted) {
                    navigator.pop();
                  }
                }
              },
            );

            // Wrap with InkWell for the long-press context menu
            return InkWell(
              onLongPress: () {
                if (!item.isDirectory) {
                  _showFileHistoryMenu(context, ref, item);
                }
              },
              child: tile,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Text('Error loading tree: $e'),
    );
  }
}