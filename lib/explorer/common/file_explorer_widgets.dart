// lib/explorer/common/file_explorer_widgets.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart'; // NEW: For projectHierarchyProvider
import '../../editor/plugins/plugin_registry.dart';
import '../plugins/file_explorer/file_explorer_state.dart';
import 'file_explorer_commands.dart';
import '../explorer_plugin_registry.dart';

// REFACTOR: The DirectoryView is now purely declarative.
class DirectoryView extends ConsumerStatefulWidget {
  // ... constructor ...
  final String directory;
  final String projectRootUri;
  final FileExplorerSettings state;

  const DirectoryView({
    super.key,
    required this.directory,
    required this.projectRootUri,
    required this.state,
  });

  @override
  ConsumerState<DirectoryView> createState() => _DirectoryViewState();
}

class _DirectoryViewState extends ConsumerState<DirectoryView> {
  @override
  void initState() {
    super.initState();
    // FIX: Use `ref.read` to call the notifier method, not to watch.
    // This is a one-time action.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // We check the state directly before firing the request to avoid re-fetching.
        if (ref.read(projectHierarchyProvider)[widget.directory] == null) {
          ref
              .read(projectHierarchyProvider.notifier)
              .loadDirectory(widget.directory);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Watch the new StateNotifierProvider directly. This will get the state
    // map and rebuild the widget whenever the map changes.
    final directoryContents =
        ref.watch(projectHierarchyProvider)[widget.directory];

    // FIX: This now correctly handles the initial loading state.
    if (directoryContents == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final sortedContents = List<DocumentFile>.from(directoryContents);
    _applySorting(sortedContents, widget.state.viewMode);

    return ListView.builder(
      key: PageStorageKey(widget.directory),
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: sortedContents.length,
      itemBuilder: (context, index) {
        final item = sortedContents[index];
        final depth =
            item.uri.split('%2F').length -
            widget.projectRootUri.split('%2F').length;
        return DirectoryItem(
          item: item,
          depth: depth,
          isExpanded: widget.state.expandedFolders.contains(item.uri),
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
          if (expanded) {
            // FIX: You must call methods on the .notifier.
            ref.read(projectHierarchyProvider.notifier).loadDirectory(item.uri);
          }
          explorerNotifier.updateSettings((settings) {
            final currentSettings = settings as FileExplorerSettings;
            final newExpanded = Set<String>.from(
              currentSettings.expandedFolders,
            );
            if (expanded) {
              newExpanded.add(item.uri);
            } else {
              newExpanded.remove(item.uri);
            }
            return currentSettings.copyWith(expandedFolders: newExpanded);
          });
        },
        childrenPadding: EdgeInsets.only(left: (depth > 0 ? 16.0 : 0)),
        children: [
          if (isExpanded)
            Consumer(
              builder: (context, ref, _) {
                final currentState =
                    ref.watch(activeExplorerSettingsProvider)
                        as FileExplorerSettings?;
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
      // Unchanged file logic
      childWidget = ListTile(
        key: ValueKey(item.uri),
        contentPadding: EdgeInsets.only(left: (depth) * 16.0 + 16.0),
        leading: FileTypeIcon(file: item),
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        subtitle:
            subtitle != null
                ? Text(subtitle!, overflow: TextOverflow.ellipsis)
                : null,
        onTap: () async {
          final success = await ref
              .read(appNotifierProvider.notifier)
              .openFileInEditor(item);

          if (success && context.mounted) {
            Navigator.of(context).pop();
          }
        },
      );
    }

    return GestureDetector(
      onLongPress: () => showFileContextMenu(context, ref, item),
      child: childWidget,
    );
  }
}

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
