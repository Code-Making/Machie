// lib/explorer/common/file_explorer_widgets.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../editor/plugins/plugin_registry.dart';
import '../plugins/file_explorer/file_explorer_state.dart';
import 'file_explorer_commands.dart';
import 'file_explorer_dialogs.dart';
import '../../utils/toast.dart';
import '../../editor/services/editor_service.dart'; // REFACTOR

// ... (DirectoryView is mostly unchanged, but its dependency is simpler) ...
class DirectoryView extends ConsumerWidget {
  final String directory;
  final String projectRootUri;
  final String projectId;
  final FileExplorerSettings state;

  const DirectoryView({
    super.key,
    required this.directory,
    required this.projectRootUri,
    required this.projectId,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(
      currentProjectDirectoryContentsProvider(directory),
    );

    return contentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (contents) {
        _applySorting(contents, state.viewMode);

        return ListView.builder(
          key: PageStorageKey(directory), // Preserve scroll position
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: contents.length,
          itemBuilder: (context, index) {
            final item = contents[index];
            final depth =
                item.uri.split('%2F').length - projectRootUri.split('%2F').length;
            return DirectoryItem(
              item: item,
              depth: depth,
              isExpanded: state.expandedFolders.contains(item.uri),
              projectId: projectId,
            );
          },
        );
      },
    );
  }

  void _applySorting(List<DocumentFile> contents, FileExplorerViewMode mode) {
    contents.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (mode) {
        case FileExplorerViewMode.sortByNameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case FileExplorerViewMode.sortByDateModified:
          return b.modifiedDate.compareTo(a.modifiedDate);
        default: // Also handles null and sortByNameAsc
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
  }
}

class DirectoryItem extends ConsumerWidget {
  final DocumentFile item;
  final int depth;
  final bool isExpanded;
  final String projectId;
  final String? subtitle;

  const DirectoryItem({
    super.key,
    required this.item,
    required this.depth,
    required this.isExpanded,
    required this.projectId,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REFACTOR: Use the simpler notifier provider.
    final fileExplorerNotifier =
        ref.read(fileExplorerNotifierProvider(projectId));

    Widget childWidget;
    if (item.isDirectory) {
      childWidget = ExpansionTile(
        key: PageStorageKey<String>(item.uri),
        leading: Icon(
          isExpanded ? Icons.folder_open : Icons.folder,
          color: Colors.yellow.shade700,
        ),
        title: Text(item.name),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          fileExplorerNotifier.toggleFolderExpansion(item.uri);
        },
        childrenPadding: EdgeInsets.only(left: (depth > 0 ? 16.0 : 0)),
        children: [
          if (isExpanded)
            Consumer(
              builder: (context, ref, _) {
                // REFACTOR: Read state from the simpler provider.
                final currentState =
                    ref.watch(fileExplorerStateProvider(projectId));
                final project =
                    ref.watch(appNotifierProvider).value!.currentProject!;
                return DirectoryView(
                  directory: item.uri,
                  projectRootUri: project.rootUri,
                  projectId: projectId,
                  state: currentState,
                );
              },
            ),
        ],
      );
    } else {
      childWidget = ListTile(
        key: ValueKey(item.uri),
        contentPadding: EdgeInsets.only(left: (depth) * 16.0 + 16.0),
        leading: FileTypeIcon(file: item),
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        subtitle: subtitle != null
            ? Text(subtitle!, overflow: TextOverflow.ellipsis)
            : null,
        onTap: () async {
          // REFACTOR: Logic is now delegated to AppNotifier, which is much cleaner.
          await ref.read(appNotifierProvider.notifier).openFileInEditor(item);
        },
      );
    }

    return GestureDetector(
      onLongPress: () => showFileContextMenu(context, ref, item),
      child: childWidget,
    );
  }
}

// ... (RootPlaceholder and FileTypeIcon are unchanged) ...
class RootPlaceholder implements DocumentFile {
  @override
  final String uri;
  @override
  final bool isDirectory = true;
  @override
  String get name => '';
  @override
  int get size => 0;
  @override
  DateTime get modifiedDate => DateTime.now();
  @override
  String get mimeType => 'inode/directory';
  RootPlaceholder(this.uri);
}

class FileTypeIcon extends ConsumerWidget {
  final DocumentFile file;
  const FileTypeIcon({super.key, required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final plugin = plugins.firstWhereOrNull((p) => p.supportsFile(file));
    return plugin?.icon ?? const Icon(Icons.article_outlined);
  }
}