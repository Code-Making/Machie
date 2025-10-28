// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_explorer_view.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/dart_git.dart';

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
    // THE FIX: The top-level widget now watches the async repository provider.
    final gitRepoAsync = ref.watch(gitRepositoryProvider);

    // Use .when() to handle loading, error, and data states for the repo itself.
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
          child: Text(
            'Error loading Git repository:\n$err',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (gitRepo) {
        // If the provider successfully returns null, it means this is not a git repo.
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

        // Only build the rest of the UI if the repository was successfully loaded.
        return const Column(
          children: [
            _CommitSelector(),
            Divider(height: 1),
            Expanded(
              child: _GitDirectoryView(pathInRepo: ''),
            ),
          ],
        );
      },
    );
  }
}

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

class _GitDirectoryView extends ConsumerWidget {
  final String pathInRepo;
  final int depth;

  const _GitDirectoryView({required this.pathInRepo, this.depth = 1});

  void _showFileHistoryMenu(BuildContext context, WidgetRef ref, GitObjectDocumentFile file) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Consumer(builder: (context, ref, _) {
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
        });
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(gitTreeProvider(pathInRepo));

    return treeAsync.when(
      data: (items) {
        return generic.FileListView(
          items: items,
          expandedDirectoryUris: const {},
          depth: depth,
          onFileTapped: (file) async {
            final navigator = Navigator.of(context);
            final success = await ref.read(appNotifierProvider.notifier).openFileInEditor(file);
             if (success && context.mounted) {
              navigator.pop(); // Close the drawer
            }
          },
          onExpansionChanged: (dir, isExpanded) {
            // Not used, as clicking a directory opens a new view in this explorer type.
          },
          directoryChildrenBuilder: (directory) {
            // This explorer doesn't show nested items. Instead, clicking a folder
            // would typically navigate to a new screen showing that folder's contents.
            // For simplicity, this is not implemented here.
            return const SizedBox.shrink();
          },
          itemBuilder: (context, item, depth, defaultItem) {
            return InkWell(
              onLongPress: () {
                if (item is GitObjectDocumentFile && !item.isDirectory) {
                  _showFileHistoryMenu(context, ref, item);
                }
              },
              child: defaultItem,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Text('Error loading tree: $e'),
    );
  }
}