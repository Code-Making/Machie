// lib/explorer/common/file_explorer_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Import the generic widgets with a prefix to avoid name clashes
import 'package:machine/widgets/file_list_view.dart' as generic;

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../project/services/project_hierarchy_service.dart';
import '../plugins/file_explorer/file_explorer_state.dart';
import 'file_explorer_commands.dart';
import '../explorer_plugin_registry.dart';
import '../services/explorer_service.dart';

// (sortedDirectoryContentsProvider is unchanged)
final sortedDirectoryContentsProvider = Provider.autoDispose.family<AsyncValue<List<FileTreeNode>>, String>((ref, directoryUri) {
  final directoryState = ref.watch(directoryContentsProvider(directoryUri));
  final settings = ref.watch(activeExplorerSettingsProvider);
  final sortMode = (settings is FileExplorerSettings) ? settings.viewMode : FileExplorerViewMode.sortByNameAsc;
  return directoryState?.whenData((nodes) {
    final sortedNodes = List<FileTreeNode>.from(nodes);
    sortedNodes.sort((a, b) {
      if (a.file.isDirectory != b.file.isDirectory) return a.file.isDirectory ? -1 : 1;
      switch (sortMode) {
        case FileExplorerViewMode.sortByNameDesc: return b.file.name.toLowerCase().compareTo(a.file.name.toLowerCase());
        case FileExplorerViewMode.sortByDateModified: return b.file.modifiedDate.compareTo(a.file.modifiedDate);
        default: return a.file.name.toLowerCase().compareTo(b.file.name.toLowerCase());
      }
    });
    return sortedNodes;
  }) ?? const AsyncValue.loading();
});

// RE-IMPLEMENTED: Helper function and placeholder class
bool _isDropAllowed(ProjectDocumentFile draggedFile, ProjectDocumentFile targetFolder, FileHandler fileHandler) {
  if (!targetFolder.isDirectory) return false;
  if (draggedFile.uri == targetFolder.uri) return false;
  if (targetFolder.uri.startsWith(draggedFile.uri)) return false;
  return true;
}

class RootPlaceholder implements ProjectDocumentFile {
  @override final String uri;
  @override final bool isDirectory = true;
  @override String get name => '';
  @override int get size => 0;
  @override DateTime get modifiedDate => DateTime.now();
  @override String get mimeType => 'inode/directory';
  RootPlaceholder(this.uri);
}

/// NEW: The decorator widget that adds project-specific features like
/// drag-and-drop and context menus to any widget.
class ProjectFileItemDecorator extends ConsumerStatefulWidget {
  final ProjectDocumentFile item;
  final Widget child;

  const ProjectFileItemDecorator({super.key, required this.item, required this.child});

  @override
  ConsumerState<ProjectFileItemDecorator> createState() => _ProjectFileItemDecoratorState();
}

class _ProjectFileItemDecoratorState extends ConsumerState<ProjectFileItemDecorator> {
  bool _isHoveredByDraggable = false;

  @override
  Widget build(BuildContext context) {
    final fileHandler = ref.watch(projectRepositoryProvider)!.fileHandler;
    final explorerService = ref.read(explorerServiceProvider);

    final Draggable<ProjectDocumentFile> draggableItem = LongPressDraggable<ProjectDocumentFile>(
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
          color: _isHoveredByDraggable ? Theme.of(context).colorScheme.primary.withAlpha(70) : null,
          child: draggableItem,
        );
      },
      onWillAcceptWithDetails: (details) {
        final isAllowed = _isDropAllowed(details.data, widget.item, fileHandler);
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        child: ListTile(
          dense: true,
          leading: generic.FileTypeIcon(file: widget.item),
          title: Text(widget.item.name, style: const TextStyle(fontSize: 14.0, color: Colors.white), overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// This is the main "smart" widget for the project's file explorer.
/// It fetches data, provides project-specific callbacks, and uses the
/// [ProjectFileItemDecorator] to add features to the generic [FileListView].
class DirectoryView extends ConsumerWidget {
  final String directoryUri;
  final int depth;

  const DirectoryView({super.key, required this.directoryUri, this.depth = 1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortedDirectoryState = ref.watch(sortedDirectoryContentsProvider(directoryUri));
    final settings = ref.watch(activeExplorerSettingsProvider) as FileExplorerSettings?;

    if (settings == null) return const Center(child: CircularProgressIndicator());

    return sortedDirectoryState.when(
      data: (nodes) {
        return generic.FileListView(
          items: nodes.map((node) => node.file).toList(),
          expandedDirectoryUris: settings.expandedFolders,
          depth: depth,
          onFileTapped: (file) async {
            final navigator = Navigator.of(context);
            final success = await ref.read(appNotifierProvider.notifier).openFileInEditor(file as ProjectDocumentFile);
            if (success && context.mounted) navigator.pop();
          },
          onExpansionChanged: (directory, isExpanded) {
            if (isExpanded) ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(directory.uri);
            ref.read(activeExplorerNotifierProvider).updateSettings((s) {
              final currentSettings = s as FileExplorerSettings;
              final newExpanded = Set<String>.from(currentSettings.expandedFolders);
              if (isExpanded) newExpanded.add(directory.uri);
              else newExpanded.remove(directory.uri);
              return currentSettings.copyWith(expandedFolders: newExpanded);
            });
          },
          directoryChildrenBuilder: (directory) => DirectoryView(directoryUri: directory.uri, depth: depth + 1),
          // HERE IS THE DECORATION LOGIC
          itemBuilder: (context, item, depth, defaultItem) {
            return ProjectFileItemDecorator(
              item: item as ProjectDocumentFile,
              child: defaultItem,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}

// RE-IMPLEMENTED: The RootDropZone
class RootDropZone extends ConsumerWidget {
  final String projectRootUri;
  final bool isDragActive;

  const RootDropZone({super.key, required this.projectRootUri, required this.isDragActive});

  static const _kActiveHeight = 60.0;
  static const _kAnimationDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileHandler = ref.watch(projectRepositoryProvider)!.fileHandler;
    return DragTarget<ProjectDocumentFile>(
      builder: (context, candidateData, rejectedData) {
        final bool shouldBeExpanded = isDragActive || candidateData.isNotEmpty;
        final bool canAccept = candidateData.isNotEmpty && _isDropAllowed(candidateData.first!, RootPlaceholder(projectRootUri), fileHandler);
        final highlightDecoration = BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(70),
          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2.0),
          borderRadius: BorderRadius.circular(8),
        );
        final normalDecoration = BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withAlpha(150),
          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(100)),
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
                  Icon(Icons.move_up, color: Theme.of(context).colorScheme.onSurface),
                  const SizedBox(width: 12),
                  Text('Move to Project Root', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
            ),
          ),
        );
      },
      onWillAcceptWithDetails: (details) => _isDropAllowed(details.data, RootPlaceholder(projectRootUri), fileHandler),
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