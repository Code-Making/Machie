// =========================================
// UPDATED: lib/explorer/common/file_explorer_widgets.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../editor/plugins/plugin_registry.dart';
import '../plugins/file_explorer/file_explorer_state.dart';
import 'file_explorer_commands.dart';
import '../explorer_plugin_registry.dart';
import '../services/explorer_service.dart';

bool _isDropAllowed(DocumentFile draggedFile, DocumentFile targetFolder) {
  if (!targetFolder.isDirectory) return false;
  if (draggedFile.uri == targetFolder.uri) return false;
  if (targetFolder.uri.startsWith(draggedFile.uri)) return false;

  final parentUri = draggedFile.uri.substring(
    0,
    draggedFile.uri.lastIndexOf('%2F'),
  );
  if (parentUri == targetFolder.uri) return false;

  return true;
}

// ... DirectoryView and RootDropZone are unchanged ...
class DirectoryView extends ConsumerStatefulWidget {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
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
    final directoryContents =
        ref.watch(projectHierarchyProvider)[widget.directory];

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
      padding: const EdgeInsets.only(top: 8.0),
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

class RootDropZone extends ConsumerWidget {
  final String projectRootUri;
  const RootDropZone({super.key, required this.projectRootUri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<DocumentFile>(
      builder: (context, candidateData, rejectedData) {
        final canAccept =
            candidateData.isNotEmpty &&
            _isDropAllowed(
              candidateData.first!,
              RootPlaceholder(projectRootUri),
            );

        return AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: canAccept ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !canAccept,
            child: Container(
              margin: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(50),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.move_up),
                  SizedBox(width: 8),
                  Text('Move to Project Root'),
                ],
              ),
            ),
          ),
        );
      },
      onWillAcceptWithDetails: (details) =>
          _isDropAllowed(details.data, RootPlaceholder(projectRootUri)),
      onAcceptWithDetails: (details) {
        ref
            .read(explorerServiceProvider)
            .moveItem(details.data, RootPlaceholder(projectRootUri));
      },
    );
  }
}

// =======================================================================
// THE MAIN FIX is in DirectoryItem and its _DirectoryItemState
// =======================================================================

class DirectoryItem extends ConsumerStatefulWidget {
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
  ConsumerState<DirectoryItem> createState() => _DirectoryItemState();
}

class _DirectoryItemState extends ConsumerState<DirectoryItem> {
  // THE FIX: Use local state for the hover effect.
  bool _isHoveredByDraggable = false;

  static const double _kBaseIndent = 16.0;
  static const double _kFontSize = 14.0;
  static const double _kVerticalPadding = 2.0;

  @override
  Widget build(BuildContext context) {
    final itemContent = widget.item.isDirectory
        ? _buildDirectoryTile()
        : _buildFileTile();

    // The Draggable wraps the entire item.
    return LongPressDraggable<DocumentFile>(
      data: widget.item,
      feedback: _buildDragFeedback(),
      childWhenDragging: Opacity(opacity: 0.5, child: itemContent),
      delay: const Duration(milliseconds: 500),
      // THE FIX: The complex onDragEnd logic is no longer needed here.
      // All actions are now handled by the DragTargets.
      child: itemContent,
    );
  }

  Widget _buildFileTile() {
    final double currentIndent = widget.depth * _kBaseIndent;
    return GestureDetector(
      onTap: () async {
        final navigator = Navigator.of(context);
        final success = await ref
            .read(appNotifierProvider.notifier)
            .openFileInEditor(widget.item);
        if (success && mounted) {
          navigator.pop();
        }
      },
      onLongPress: () {
        // Allow long press to open context menu directly on files
        showFileContextMenu(context, ref, widget.item);
      },
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(
          left: currentIndent + _kBaseIndent,
          top: _kVerticalPadding,
          bottom: _kVerticalPadding,
        ),
        leading: FileTypeIcon(file: widget.item),
        title: Text(
          widget.item.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: _kFontSize),
        ),
        subtitle: widget.subtitle != null
            ? Text(
                widget.subtitle!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: _kFontSize - 2),
              )
            : null,
      ),
    );
  }

  Widget _buildDirectoryTile() {
    final double currentIndent = widget.depth * _kBaseIndent;

    // THE FIX: The visible part of the tile is built separately so it can
    // be wrapped in a DragTarget without covering its children.
    Widget tileContent = Container(
      color: _isHoveredByDraggable
          ? Theme.of(context).colorScheme.primary.withAlpha(70)
          : null,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(
          left: currentIndent,
          right: 8.0,
          top: _kVerticalPadding,
          bottom: _kVerticalPadding,
        ),
        leading: Icon(
          widget.isExpanded ? Icons.folder_open : Icons.folder,
          color: Colors.yellow.shade700,
        ),
        title: Text(
          widget.item.name,
          style: const TextStyle(fontSize: _kFontSize),
        ),
        subtitle: widget.subtitle != null
            ? Text(
                widget.subtitle!,
                style: const TextStyle(fontSize: _kFontSize - 2),
              )
            : null,
        trailing: const Icon(Icons.chevron_right),
      ),
    );

    // THE FIX: The DragTarget now wraps ONLY the visible tile content.
    final tileWithDropTarget = DragTarget<DocumentFile>(
      builder: (context, candidateData, rejectedData) {
        return tileContent;
      },
      onWillAcceptWithDetails: (details) {
        final draggedFile = details.data;
        // Accept the drop if it's a valid move OR if it's being dropped on itself.
        final bool isSelfDrop = draggedFile.uri == widget.item.uri;
        final bool isAllowedMove = _isDropAllowed(draggedFile, widget.item);

        if (isAllowedMove) {
          // Only show the hover highlight for a valid MOVE operation.
          setState(() { _isHoveredByDraggable = true; });
        }
        
        return isAllowedMove || isSelfDrop;
      },
      onAcceptWithDetails: (details) {
        final draggedFile = details.data;
        // THE FIX: This is the core logic. Check if the drop is on the source item.
        if (draggedFile.uri == widget.item.uri) {
          // If it is, show the context menu instead of moving.
          showFileContextMenu(context, ref, widget.item);
        } else {
          // Otherwise, perform the move operation.
          ref.read(explorerServiceProvider).moveItem(draggedFile, widget.item);
        }
        // Always reset hover state after any accepted drop.
        setState(() { _isHoveredByDraggable = false; });
      },
      onLeave: (details) {
        setState(() { _isHoveredByDraggable = false; });
      },
    );

    // The ExpansionTile now uses the DragTarget-wrapped tile as its header
    // and the nested DirectoryView as its child. This physically separates the
    // parent drop zone from the children.
    return ExpansionTile(
      key: PageStorageKey<String>(widget.item.uri),
      // Use a custom header builder to insert our DragTarget tile.
      title: tileWithDropTarget,
      // Remove default padding and indicators, as our custom tile handles them.
      tilePadding: EdgeInsets.zero,
      trailing: const SizedBox.shrink(),
      leading: const SizedBox.shrink(),
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: widget.isExpanded,
      onExpansionChanged: (expanded) {
        if (expanded) {
          ref
              .read(projectHierarchyProvider.notifier)
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

// ... RootPlaceholder and FileTypeIcon are unchanged ...
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