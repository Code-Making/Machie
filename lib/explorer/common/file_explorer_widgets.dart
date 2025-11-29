// FILE: lib/explorer/common/file_explorer_widgets.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project/project_repository.dart';
import '../../project/services/project_hierarchy_service.dart';
import '../../widgets/file_list_view.dart' as generic;
import '../explorer_plugin_registry.dart';
import '../plugins/file_explorer/file_explorer_state.dart';
import '../services/explorer_service.dart';
import 'file_explorer_commands.dart';

// --- Providers ---

/// Granular provider: Returns true if the specific [folderUri] is currently expanded.
final isFolderExpandedProvider =
    Provider.autoDispose.family<bool, String>((ref, folderUri) {
  final expandedSet = ref.watch(fileExplorerExpandedFoldersProvider);
  return expandedSet.contains(folderUri);
});

/// Returns the sorted contents of a directory.
final sortedDirectoryContentsProvider = Provider.autoDispose
    .family<AsyncValue<List<FileTreeNode>>, String>((ref, directoryUri) {
  final directoryState = ref.watch(directoryContentsProvider(directoryUri));

  final sortMode = ref.watch(activeExplorerSettingsProvider.select((s) {
    if (s is FileExplorerSettings) return s.viewMode;
    return FileExplorerViewMode.sortByNameAsc;
  }));

  return directoryState?.whenData((nodes) {
        final sortedNodes = List<FileTreeNode>.from(nodes);
        sortedNodes.sort((a, b) {
          if (a.file.isDirectory != b.file.isDirectory) {
            return a.file.isDirectory ? -1 : 1;
          }
          switch (sortMode) {
            case FileExplorerViewMode.sortByNameDesc:
              return b.file.name.toLowerCase().compareTo(
                    a.file.name.toLowerCase(),
                  );
            case FileExplorerViewMode.sortByDateModified:
              return b.file.modifiedDate.compareTo(a.file.modifiedDate);
            default:
              return a.file.name.toLowerCase().compareTo(
                    b.file.name.toLowerCase(),
                  );
          }
        });
        return sortedNodes;
      }) ??
      const AsyncValue.loading();
});

bool _isDropAllowed(
  ProjectDocumentFile draggedFile,
  ProjectDocumentFile targetFolder,
  FileHandler fileHandler,
) {
  if (!targetFolder.isDirectory) return false;
  if (draggedFile.uri == targetFolder.uri) return false;
  if (targetFolder.uri.startsWith(draggedFile.uri)) return false;
  return true;
}

class RootPlaceholder implements ProjectDocumentFile {
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

class DirectoryView extends ConsumerWidget {
  final String directoryUri;
  final int depth;

  const DirectoryView({super.key, required this.directoryUri, this.depth = 1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortedDirectoryState = ref.watch(
      sortedDirectoryContentsProvider(directoryUri),
    );

    return sortedDirectoryState.when(
      data: (nodes) {
        return ListView.builder(
          key: PageStorageKey(directoryUri),
          padding: const EdgeInsets.only(top: 0.0),
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: nodes.length,
          itemBuilder: (context, index) {
            final node = nodes[index];
            return _FileExplorerItem(
              item: node.file,
              depth: depth,
            );
          },
        );
      },
      // Don't show a spinner for every folder while building the tree recursively
      // Just show nothing until loaded.
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text('Error: $err', style: const TextStyle(color: Colors.red, fontSize: 12)),
      ),
    );
  }
}

class _FileExplorerItem extends ConsumerWidget {
  final ProjectDocumentFile item;
  final int depth;

  const _FileExplorerItem({required this.item, required this.depth});

  static const double _kIndentPerLevel = 16.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void onFileTapped() async {
      final navigator = Navigator.of(context);
      final success = await ref
          .read(appNotifierProvider.notifier)
          .openFileInEditor(item);
      
      if (success && context.mounted && navigator.canPop()) {
        navigator.pop();
      }
    }

    void onExpansionChanged(bool isExpanded) {
      if (isExpanded) {
        ref
            .read(projectHierarchyServiceProvider.notifier)
            .loadDirectory(item.uri);
      }
      ref.read(fileExplorerExpandedFoldersProvider.notifier).toggle(item.uri, isExpanded);
    }

    Widget tile;
    if (item.isDirectory) {
      final isExpanded = ref.watch(isFolderExpandedProvider(item.uri));

      tile = ExpansionTile(
        key: PageStorageKey<String>(item.uri),
        tilePadding: EdgeInsets.only(left: depth * _kIndentPerLevel, right: 8.0),
        leading: Icon(
          isExpanded ? Icons.folder_open : Icons.folder,
          color: Colors.yellow.shade700,
          // Removed manual size, reverting to default
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontSize: 14.0),
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: isExpanded,
        onExpansionChanged: onExpansionChanged,
        children: [
          // FIX: Removed 'if (isExpanded)' check.
          // ExpansionTile needs the child to exist to animate its height.
          DirectoryView(directoryUri: item.uri, depth: depth + 1),
        ],
      );
    } else {
      tile = ListTile(
        onTap: onFileTapped,
        dense: true,
        contentPadding: EdgeInsets.only(
          left: depth * _kIndentPerLevel,
          right: 8.0,
        ),
        leading: generic.FileTypeIcon(file: item),
        title: Text(
          item.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14.0),
        ),
      );
    }

    return ProjectFileItemDecorator(
      item: item,
      child: tile,
    );
  }
}

class ProjectFileItemDecorator extends ConsumerStatefulWidget {
  final ProjectDocumentFile item;
  final Widget child;

  const ProjectFileItemDecorator({
    super.key,
    required this.item,
    required this.child,
  });

  @override
  ConsumerState<ProjectFileItemDecorator> createState() =>
      _ProjectFileItemDecoratorState();
}

class _ProjectFileItemDecoratorState
    extends ConsumerState<ProjectFileItemDecorator> {
  bool _isHoveredByDraggable = false;

  @override
  Widget build(BuildContext context) {
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;
    final explorerService = ref.read(explorerServiceProvider);

    if (fileHandler == null) return widget.child;

    final Draggable<ProjectDocumentFile> draggableItem =
        LongPressDraggable<ProjectDocumentFile>(
      data: widget.item,
      feedback: _buildDragFeedback(),
      childWhenDragging: Opacity(opacity: 0.5, child: widget.child),
      delay: const Duration(milliseconds: 300),
      onDragEnd: (details) {
        if (!details.wasAccepted) {
          showFileContextMenu(context, ref, widget.item);
        }
      },
      child: widget.child,
    );

    if (!widget.item.isDirectory) {
      return draggableItem;
    }

    return DragTarget<ProjectDocumentFile>(
      builder: (context, candidateData, rejectedData) {
        return Container(
          color: _isHoveredByDraggable
              ? Theme.of(context).colorScheme.primary.withAlpha(70)
              : null,
          child: draggableItem,
        );
      },
      onWillAcceptWithDetails: (details) {
        final isAllowed = _isDropAllowed(
          details.data,
          widget.item,
          fileHandler,
        );
        if (mounted) setState(() => _isHoveredByDraggable = isAllowed);
        return isAllowed;
      },
      onAcceptWithDetails: (details) {
        final draggedFile = details.data;
        final targetFolder = widget.item;
        final parentUri = fileHandler.getParentUri(draggedFile.uri);

        if (parentUri == targetFolder.uri) {
          showFileContextMenu(context, ref, draggedFile);
        } else {
          explorerService.moveItem(draggedFile, targetFolder);
        }
        if (mounted) setState(() => _isHoveredByDraggable = false);
      },
      onLeave: (data) {
        if (mounted) setState(() => _isHoveredByDraggable = false);
      },
    );
  }

  Widget _buildDragFeedback() {
    return Material(
      elevation: 4.0,
      color: Theme.of(context).colorScheme.primary.withAlpha(180),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: ListTile(
          dense: true,
          leading: generic.FileTypeIcon(file: widget.item),
          title: Text(
            widget.item.name,
            style: const TextStyle(fontSize: 14.0, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class RootDropZone extends ConsumerWidget {
  final String projectRootUri;
  final bool isDragActive;

  const RootDropZone({
    super.key,
    required this.projectRootUri,
    required this.isDragActive,
  });

  static const _kActiveHeight = 60.0;
  static const _kAnimationDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;
    
    if (fileHandler == null) return const SizedBox.shrink();

    return DragTarget<ProjectDocumentFile>(
      builder: (context, candidateData, rejectedData) {
        final bool shouldBeExpanded = isDragActive || candidateData.isNotEmpty;
        final bool canAccept =
            candidateData.isNotEmpty &&
            _isDropAllowed(
              candidateData.first!,
              RootPlaceholder(projectRootUri),
              fileHandler,
            );
        final highlightDecoration = BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(70),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 2.0,
          ),
          borderRadius: BorderRadius.circular(8),
        );
        final normalDecoration = BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withAlpha(150),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
          ),
          borderRadius: BorderRadius.circular(8),
        );
        return AnimatedContainer(
          duration: _kAnimationDuration,
          height: shouldBeExpanded ? _kActiveHeight : 0.0,
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: canAccept ? highlightDecoration : normalDecoration,
          child: ClipRect(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.move_up,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Move to Project Root',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      onWillAcceptWithDetails:
          (details) => _isDropAllowed(
            details.data,
            RootPlaceholder(projectRootUri),
            fileHandler,
          ),
      onAcceptWithDetails: (details) {
        final draggedFile = details.data;
        final targetFolder = RootPlaceholder(projectRootUri);
        final parentUri = fileHandler.getParentUri(draggedFile.uri);
        if (parentUri != targetFolder.uri) {
          ref.read(explorerServiceProvider).moveItem(draggedFile, targetFolder);
        } else {
          showFileContextMenu(context, ref, draggedFile);
        }
      },
    );
  }
}