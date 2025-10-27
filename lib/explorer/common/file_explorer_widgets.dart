import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../editor/plugins/plugin_registry.dart';
import '../../project/services/project_hierarchy_service.dart';
import '../plugins/file_explorer/file_explorer_state.dart';
import 'file_explorer_commands.dart';
import '../explorer_plugin_registry.dart';
import '../services/explorer_service.dart';

/// A memoized provider that returns a sorted list of nodes for a given directory.
///
/// This provider performs the sorting operation, preventing the UI from re-sorting
/// on every rebuild. It will only re-compute its state if either the raw
/// directory contents change or the sort mode in the settings changes.
final sortedDirectoryContentsProvider = Provider.autoDispose
    .family<AsyncValue<List<FileTreeNode>>, String>((ref, directoryUri) {
      final directoryState = ref.watch(directoryContentsProvider(directoryUri));

      final settings = ref.watch(activeExplorerSettingsProvider);
      final sortMode =
          (settings is FileExplorerSettings)
              ? settings.viewMode
              : FileExplorerViewMode.sortByNameAsc; // Provide a safe default.

      // 3. When the async data is available, perform the sort.
      //    Riverpod automatically caches the result.
      return directoryState?.whenData((nodes) {
            // Create a mutable copy of the list to sort.
            final sortedNodes = List<FileTreeNode>.from(nodes);
            _applySorting(sortedNodes, sortMode);
            return sortedNodes;
          }) ??
          const AsyncValue.loading(); // Handle the initial null state.
    });

void _applySorting(List<FileTreeNode> contents, FileExplorerViewMode mode) {
  contents.sort((a, b) {
    if (a.file.isDirectory != b.file.isDirectory) {
      return a.file.isDirectory ? -1 : 1;
    }
    switch (mode) {
      case FileExplorerViewMode.sortByNameDesc:
        return b.file.name.toLowerCase().compareTo(a.file.name.toLowerCase());
      case FileExplorerViewMode.sortByDateModified:
        return b.file.modifiedDate.compareTo(a.file.modifiedDate);
      default: // sortByNameAsc
        return a.file.name.toLowerCase().compareTo(b.file.name.toLowerCase());
    }
  });
}

// (The _isDropAllowed function remains unchanged)
bool _isDropAllowed(
  ProjectDocumentFile draggedFile,
  ProjectDocumentFile targetFolder,
  FileHandler fileHandler,
) {
  if (!targetFolder.isDirectory) return false;
  if (draggedFile.uri == targetFolder.uri) return false;
  // This check prevents dropping a folder into one of its own descendants.
  if (targetFolder.uri.startsWith(draggedFile.uri)) return false;

  // THE FIX: The check to prevent dropping into the same parent is REMOVED.
  // We will now allow this drop and handle it in the `onAccept` callback.
  // final parentUri = fileHandler.getParentUri(draggedFile.uri);
  // if (parentUri == targetFolder.uri) return false;

  return true;
}

class DirectoryView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // === CHANGED ===
    // Watch the NEW provider that returns the pre-sorted data.
    final sortedDirectoryState = ref.watch(
      sortedDirectoryContentsProvider(directory),
    );

    // The widget now reacts to the new provider's state.
    return sortedDirectoryState.when(
      data: (sortedNodes) {
        // The 'sortedNodes' list is already sorted!
        final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;
        if (fileHandler == null) return const SizedBox.shrink();

        // The ListView.builder implementation remains the same, but it's
        // now more efficient because it doesn't trigger a sort.
        return ListView.builder(
          key: PageStorageKey(directory),
          padding: const EdgeInsets.only(top: 8.0),
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: sortedNodes.length,
          itemBuilder: (context, index) {
            final itemNode = sortedNodes[index];
            final item = itemNode.file;
            final pathSegments = fileHandler
                .getPathForDisplay(item.uri, relativeTo: projectRootUri)
                .split('/');

            // Handle root level items correctly (depth should be 1, not 0)
            final depth =
                pathSegments.length > 1 || pathSegments.first.isNotEmpty
                    ? pathSegments.length
                    : 1;

            return DirectoryItem(
              item: item,
              depth: depth,
              isExpanded: state.expandedFolders.contains(item.uri),
            );
          },
        );
      },
      loading:
          () => const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          ),
      error:
          (err, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Error loading directory:\n$err',
                textAlign: TextAlign.center,
              ),
            ),
          ),
    );
  }
}

// (RootDropZone, DirectoryItem, _DirectoryItemState, RootPlaceholder, FileTypeIcon all remain the same as the previous correct version)
// For completeness, here are the unchanged parts again.

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
        // ### THIS IS THE FIX ###
        // The zone should be expanded if the parent says a drag is active
        // OR if a drag is happening directly over this zone. This prevents
        // the flicker when moving from the parent to the child target.
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
          color: Theme.of(context).colorScheme.surfaceVariant.withAlpha(150),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
          ),
          borderRadius: BorderRadius.circular(8),
        );

        return AnimatedContainer(
          duration: _kAnimationDuration,
          // The height is now controlled by our robust `shouldBeExpanded` flag.
          height: shouldBeExpanded ? _kActiveHeight : 0.0,
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: canAccept ? highlightDecoration : normalDecoration,
          child: ClipRect(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
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

        // Check if the file is already in the target folder.
        if (parentUri == targetFolder.uri) {
          // This is a no-op drop, so show the context menu.
          showFileContextMenu(context, ref, draggedFile);
        } else {
          // This is a real move, so execute it.
          ref.read(explorerServiceProvider).moveItem(draggedFile, targetFolder);
        }
      },
    );
  }
}

class DirectoryItem extends ConsumerStatefulWidget {
  final ProjectDocumentFile item;
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
  ConsumerState<DirectoryItem> createState() => _DirectoryItemState();
}

class _DirectoryItemState extends ConsumerState<DirectoryItem> {
  bool _isHoveredByDraggable = false;

  static const double _kIndentPerLevel = 16.0;
  static const double _kFontSize = 14.0;
  static const double _kVerticalPadding = 2.0;

  @override
  Widget build(BuildContext context) {
    final itemContent =
        widget.item.isDirectory ? _buildDirectoryTile() : _buildFileTile();

    return LongPressDraggable<ProjectDocumentFile>(
      data: widget.item,
      feedback: _buildDragFeedback(),
      childWhenDragging: Opacity(opacity: 0.5, child: itemContent),
      delay: const Duration(milliseconds: 500),
      onDragEnd: (details) {
        if (!details.wasAccepted) {
          showFileContextMenu(context, ref, widget.item);
        }
      },
      child: itemContent,
    );
  }

  Widget _buildFileTile() {
    // The indent is based on how many levels deep we are.
    // Root items (depth=1) get 1 level of indent. Nested items get more.
    final double currentIndent = widget.depth * _kIndentPerLevel;

    return ListTile(
      onTap: () async {
        final navigator = Navigator.of(context);
        final success = await ref
            .read(appNotifierProvider.notifier)
            .openFileInEditor(widget.item);
        if (success && mounted) {
          navigator.pop();
        }
      },
      dense: true,
      // The contentPadding's left value IS the indent.
      contentPadding: EdgeInsets.only(
        left: currentIndent,
        top: _kVerticalPadding,
        bottom: _kVerticalPadding,
        right: 8.0,
      ),
      leading: FileTypeIcon(file: widget.item),
      title: Text(
        widget.item.name,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _kFontSize),
      ),
      subtitle:
          widget.subtitle != null
              ? Text(
                widget.subtitle!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: _kFontSize - 2),
              )
              : null,
    );
  }

  Widget _buildDirectoryTile() {
    // The indent calculation is now identical to the file tile.
    final double currentIndent = widget.depth * _kIndentPerLevel;
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;
    if (fileHandler == null) return const SizedBox.shrink();

    // We build the ExpansionTile directly, without a nested ListTile.
    final expansionTile = ExpansionTile(
      key: PageStorageKey<String>(widget.item.uri),

      // The tilePadding is set to match the file's contentPadding exactly.
      tilePadding: EdgeInsets.only(
        left: currentIndent,
        top: _kVerticalPadding,
        bottom: _kVerticalPadding,
        right: 8.0,
      ),

      // The icon is placed in the 'leading' slot.
      leading: Icon(
        widget.isExpanded ? Icons.folder_open : Icons.folder,
        color: Colors.yellow.shade700,
      ),

      // The title is now just the Text widget.
      title: Text(
        widget.item.name,
        style: const TextStyle(fontSize: _kFontSize),
      ),

      // Let the ExpansionTile handle its own animated trailing arrow.
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: widget.isExpanded,
      onExpansionChanged: (expanded) {
        if (expanded) {
          ref
              .read(projectHierarchyServiceProvider.notifier)
              .loadDirectory(widget.item.uri);
        }
        ref.read(activeExplorerNotifierProvider).updateSettings((settings) {
          final currentSettings = settings as FileExplorerSettings;
          final newExpanded = Set<String>.from(currentSettings.expandedFolders);
          if (expanded) {
            newExpanded.add(widget.item.uri);
          } else {
            newExpanded.remove(widget.item.uri);
          }
          return currentSettings.copyWith(expandedFolders: newExpanded);
        });
      },
      children: [
        if (widget.isExpanded)
          Consumer(
            builder: (context, ref, _) {
              final currentState =
                  ref.watch(activeExplorerSettingsProvider)
                      as FileExplorerSettings?;
              final project =
                  ref.watch(appNotifierProvider).value!.currentProject!;
              if (currentState == null) return const SizedBox.shrink();
              return DirectoryView(
                directory: widget.item.uri,
                projectRootUri: project.rootUri,
                state: currentState,
              );
            },
          ),
      ],
    );

    // The DragTarget now wraps the entire ExpansionTile.
    return DragTarget<ProjectDocumentFile>(
      builder: (context, candidateData, rejectedData) {
        return Container(
          color:
              _isHoveredByDraggable
                  ? Theme.of(context).colorScheme.primary.withAlpha(70)
                  : null,
          child: expansionTile,
        );
      },
      onWillAcceptWithDetails: (details) {
        final isAllowed = _isDropAllowed(
          details.data,
          widget.item,
          fileHandler,
        );
        if (isAllowed) {
          setState(() {
            _isHoveredByDraggable = true;
          });
        }
        return isAllowed;
      },
      onAcceptWithDetails: (details) {
        final draggedFile = details.data;
        final targetFolder = widget.item;
        final parentUri = fileHandler.getParentUri(draggedFile.uri);

        // Check if the file is already in the target folder.
        if (parentUri == targetFolder.uri) {
          // This is a no-op drop, so show the context menu.
          showFileContextMenu(context, ref, draggedFile);
        } else {
          // This is a real move, so execute it.
          ref.read(explorerServiceProvider).moveItem(draggedFile, targetFolder);
        }
        setState(() {
          _isHoveredByDraggable = false;
        });
      },
      onLeave: (details) {
        setState(() {
          _isHoveredByDraggable = false;
        });
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
          leading: FileTypeIcon(file: widget.item),
          title: Text(
            widget.item.name,
            style: const TextStyle(fontSize: _kFontSize, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
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

class FileTypeIcon extends ConsumerWidget {
  final ProjectDocumentFile file;
  const FileTypeIcon({super.key, required this.file});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final plugin = plugins.firstWhereOrNull((p) => p.supportsFile(file));
    return plugin?.icon ?? const Icon(Icons.article_outlined);
  }
}
