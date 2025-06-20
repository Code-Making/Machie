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
import '../../editor/services/editor_service.dart';
import '../explorer_plugin_registry.dart'; // REFACTOR: Import generic provider

class DirectoryView extends ConsumerWidget {
  final String directory;
  final String projectRootUri;
  // REFACTOR: This widget no longer needs projectId, it's fully generic.
  final FileExplorerSettings state;

  const DirectoryView({
    super.key,
    required this.directory,
    required this.projectRootUri,
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
          key: PageStorageKey(directory),
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
            );
          },
        );
      },
    );
  }
  // ... _applySorting is unchanged ...
  void _applySorting(List<DocumentFile> contents, FileExplorerViewMode mode) {
    contents.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (mode) {
        case FileExplorerViewMode.sortByNameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case FileExplorerViewMode.sortByDateModified:
          return b.modifiedDate.compareTo(a.modifiedDate);
        default:
          return a.name.toLowerCase().compareTo(a.name.toLowerCase());
      }
    });
  }
}

class DirectoryItem extends ConsumerWidget {
  final DocumentFile item;
  final int depth;
  final bool isExpanded;
  // REFACTOR: Removed projectId
  final String? subtitle;

  const DirectoryItem({
    super.key,
    required this.item,
    required this.depth,
    required this.isExpanded,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REFACTOR: Use the generic notifier.
    final explorerNotifier = ref.read(activeExplorerNotifierProvider);

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
          // REFACTOR: Call the generic update method.
          explorerNotifier.updateSettings((settings) {
            final currentSettings = settings as FileExplorerSettings;
            final newExpanded = Set<String>.from(currentSettings.expandedFolders);
            if (newExpanded.contains(item.uri)) {
              newExpanded.remove(item.uri);
            } else {
              newExpanded.add(item.uri);
            }
            return currentSettings.copyWith(expandedFolders: newExpanded);
          });
        },
        childrenPadding: EdgeInsets.only(left: (depth > 0 ? 16.0 : 0)),
        children: [
          if (isExpanded)
            Consumer(
              builder: (context, ref, _) {
                // REFACTOR: Use the generic settings provider.
                final currentState =
                    ref.watch(activeExplorerSettingsProvider) as FileExplorerSettings?;
                final project =
                    ref.watch(appNotifierProvider).value!.currentProject!;
                if (currentState == null) return const SizedBox.shrink();
                return DirectoryView(
                  directory: item.uri,
                  projectRootUri: project.rootUri,
                  state: currentState,
                );
              },
            ),
        ],
      );
    } else {
      // ... ListTile is unchanged ...
      childWidget = ListTile(
        key: ValueKey(item.uri),
        contentPadding: EdgeInsets.only(left: (depth) * 16.0 + 16.0),
        leading: FileTypeIcon(file: item),
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        subtitle:
            subtitle != null ? Text(subtitle!, overflow: TextOverflow.ellipsis) : null,
        onTap: () async {
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
// ... RootPlaceholder and FileTypeIcon are unchanged ...