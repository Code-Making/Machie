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
    // Listen for commit changes to reset (collapse) the tree view.
    ref.listen(selectedGitCommitHashProvider, (_, __) {
      ref.read(gitExplorerExpandedFoldersProvider.notifier).state = {};
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

        // REFACTORED: The main view now just contains the recursive tree.
        return const Column(
          children: [
            _CommitSelector(),
            Divider(height: 1),
            Expanded(
              // Start the recursion from the root path.
              child: _GitRecursiveDirectoryView(pathInRepo: ''),
            ),
          ],
        );
      },
    );
  }
}

// ... (_CommitSelector remains unchanged) ...
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
              itemHeight: 60,
              items: commits.map((commit) {
                return DropdownMenuItem(
                  value: commit.hash,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(commit.message.split('\n').first, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${commit.hash.toOid()} by ${commit.author.name}', overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'JetBrainsMono')),
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

// NEW: This widget is now the core recursive part of the tree.
class _GitRecursiveDirectoryView extends ConsumerWidget {
  final String pathInRepo;
  final int depth;

  const _GitRecursiveDirectoryView({required this.pathInRepo, this.depth = 1});

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
    // Watch the data provider for the current directory level.
    final treeAsync = ref.watch(gitTreeProvider(pathInRepo));
    // Watch the global state of all expanded folders.
    final expandedPaths = ref.watch(gitExplorerExpandedFoldersProvider);

    return treeAsync.when(
      data: (items) {
        if (items.isEmpty && depth > 1) {
          return generic.FileItem(
            // Show a placeholder for empty directories
            file: VirtualDocumentFile(uri: '', name: '(empty)'),
            depth: depth,
            onTapped: _dummyCallback,
          );
        }
        
        // Use the generic, reusable FileListView.
        return generic.FileListView(
          items: items,
          expandedDirectoryUris: expandedPaths, // Pass the global expanded set.
          depth: depth,
          onFileTapped: (file) async {
            final navigator = Navigator.of(context);
            final success = await ref.read(appNotifierProvider.notifier).openFileInEditor(file);
            if (success && context.mounted) {
              navigator.pop(); // Close the drawer
            }
          },
          onExpansionChanged: (directory, isExpanded) {
            // This is the core logic for expansion.
            final path = (directory as GitObjectDocumentFile).pathInRepo;
            final notifier = ref.read(gitExplorerExpandedFoldersProvider.notifier);
            final currentSet = notifier.state;
            
            // Create a new set and add or remove the path.
            final newSet = Set<String>.from(currentSet);
            if (isExpanded) {
              newSet.add(path);
            } else {
              newSet.remove(path);
            }
            notifier.state = newSet;
          },
          directoryChildrenBuilder: (directory) {
            // This is the recursion.
            return _GitRecursiveDirectoryView(
              pathInRepo: (directory as GitObjectDocumentFile).pathInRepo,
              depth: depth + 1,
            );
          },
          itemBuilder: (context, item, depth, defaultItem) {
            // Wrap the default item to add the long-press context menu.
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

void _dummyCallback() {}