// lib/explorer/plugins/git_explorer/git_explorer_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/commit.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/project/project_models.dart';
import 'package:machine/widgets/file_list_view.dart' as generic;
import 'git_provider.dart';
import 'git_object_file.dart';
import 'git_explorer_state.dart';

class GitExplorerView extends ConsumerWidget {
  final Project project;
  const GitExplorerView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gitRepo = ref.watch(gitRepositoryProvider);

    if (gitRepo == null) {
      return const Center(
        child: Text('This project is not a Git repository.'),
      );
    }

    return Column(
      children: [
        const _CommitSelector(),
        const Divider(height: 1),
        Expanded(
          child: _GitDirectoryView(pathInRepo: ''),
        ),
      ],
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
        if (commits.isEmpty) return const SizedBox.shrink();

        final selectedCommit = commits.firstWhere((c) => c.hash == selectedHash, orElse: () => commits.first);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: DropdownButton<GitHash>(
            value: selectedCommit.hash,
            onChanged: (newHash) {
              if (newHash != null) {
                ref.read(selectedGitCommitHashProvider.notifier).state = newHash;
              }
            },
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: commits.map((commit) {
              return DropdownMenuItem(
                value: commit.hash,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(commit.hash.toOid(), style: const TextStyle(fontFamily: 'JetBrainsMono')),
                    Text(
                      commit.message.split('\n').first,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
      loading: () => const Center(child: LinearProgressIndicator()),
      error: (err, st) => Text('Error loading commits: $err'),
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
          expandedDirectoryUris: const {}, // This view is not expandable, we navigate instead
          depth: depth,
          onFileTapped: (file) {
            ref.read(appNotifierProvider.notifier).openFileInEditor(file);
          },
          onExpansionChanged: (dir, isExpanded) {
            // Not used in this simple browser
          },
          directoryChildrenBuilder: (directory) {
            // This would be for a recursive view, but we'll keep it simple
            // and re-render the whole tree on selection.
            return _GitDirectoryView(pathInRepo: (directory as GitObjectDocumentFile).pathInRepo, depth: depth + 1);
          },
          itemBuilder: (context, item, depth, defaultItem) {
            // Add the context menu here
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