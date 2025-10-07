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

// (The _isDropAllowed function remains unchanged)
bool _isDropAllowed(
  DocumentFile draggedFile,
  DocumentFile targetFolder,
  FileHandler fileHandler,
) {
  if (!targetFolder.isDirectory) return false;
  if (draggedFile.uri == targetFolder.uri) return false;
  if (targetFolder.uri.startsWith(draggedFile.uri)) return false;
  final parentUri = fileHandler.getParentUri(draggedFile.uri);
  if (parentUri == targetFolder.uri) return false;
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
    final directoryState = ref.watch(directoryContentsProvider(directory));

    if (directoryState == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return directoryState.when(
      data: (nodes) {
        final sortedContents = List<FileTreeNode>.from(nodes);
        _applySorting(sortedContents, state.viewMode);
        final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;
        if (fileHandler == null) return const SizedBox.shrink();

        return ListView.builder(
          key: PageStorageKey(directory),
          padding: const EdgeInsets.only(top: 8.0),
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: sortedContents.length,
          itemBuilder: (context, index) {
            final itemNode = sortedContents[index];
            final item = itemNode.file;
            final depth =
                fileHandler
                    .getPathForDisplay(item.uri, relativeTo: projectRootUri)
                    .split('/')
                    .where((s) => s.isNotEmpty)
                    .length;
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

  // (_applySorting remains unchanged)
  void _applySorting(List<FileTreeNode> contents, FileExplorerViewMode mode) {
    contents.sort((a, b) {
      if (a.file.isDirectory != b.file.isDirectory)
        return a.file.isDirectory ? -1 : 1;
      switch (mode) {
        case FileExplorerViewMode.sortByNameDesc:
          return b.file.name.toLowerCase().compareTo(a.file.name.toLowerCase());
        case FileExplorerViewMode.sortByDateModified:
          return b.file.modifiedDate.compareTo(a.file.modifiedDate);
        default:
          return a.file.name.toLowerCase().compareTo(b.file.name.toLowerCase());
      }
    });
  }
}

// (RootDropZone, DirectoryItem, _DirectoryItemState, RootPlaceholder, FileTypeIcon all remain the same as the previous correct version)
// For completeness, here are the unchanged parts again.

class RootDropZone extends ConsumerWidget {
  final String projectRootUri;
  const RootDropZone({super.key, required this.projectRootUri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;
    if (fileHandler == null) return const SizedBox.shrink();

    return DragTarget<DocumentFile>(
      builder: (context, candidateData, rejectedData) {
        final canAccept =
            candidateData.isNotEmpty &&
            _isDropAllowed(
              candidateData.first!,
              RootPlaceholder(projectRootUri),
              fileHandler,
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
      onWillAcceptWithDetails:
          (details) => _isDropAllowed(
            details.data,
            RootPlaceholder(projectRootUri),
            fileHandler,
          ),
      onAcceptWithDetails: (details) {
        ref
            .read(explorerServiceProvider)
            .moveItem(details.data, RootPlaceholder(projectRootUri));
      },
    );
  }
}

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
  bool _isHoveredByDraggable = false;

  static const double _kBaseIndent = 16.0;
  static const double _kFontSize = 14.0;
  static const double _kVerticalPadding = 2.0;

  @override
  Widget build(BuildContext context) {
    final itemContent =
        widget.item.isDirectory ? _buildDirectoryTile() : _buildFileTile();

    return LongPressDraggable<DocumentFile>(
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
    final double currentIndent = widget.depth * _kBaseIndent;
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
    final double currentIndent = widget.depth * _kBaseIndent;
    Widget tileContent = Container(
      color:
          _isHoveredByDraggable
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
        subtitle:
            widget.subtitle != null
                ? Text(
                  widget.subtitle!,
                  style: const TextStyle(fontSize: _kFontSize - 2),
                )
                : null,
        trailing: const SizedBox(width: 24, height: 24),
      ),
    );
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;
    if (fileHandler == null) return const SizedBox.shrink();

    final tileWithDropTarget = DragTarget<DocumentFile>(
      builder: (context, candidateData, rejectedData) {
        return tileContent;
      },
      onWillAcceptWithDetails: (details) {
        final draggedFile = details.data;
        final isSelfDrop = draggedFile.uri == widget.item.uri;
        final isAllowedMove = _isDropAllowed(
          draggedFile,
          widget.item,
          fileHandler,
        );

        if (isAllowedMove) {
          setState(() {
            _isHoveredByDraggable = true;
          });
        }

        return isAllowedMove || isSelfDrop;
      },
      onAcceptWithDetails: (details) {
        final draggedFile = details.data;
        if (draggedFile.uri == widget.item.uri) {
          showFileContextMenu(context, ref, widget.item);
        } else {
          ref.read(explorerServiceProvider).moveItem(draggedFile, widget.item);
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

    return ExpansionTile(
      key: PageStorageKey<String>(widget.item.uri),
      title: tileWithDropTarget,
      tilePadding: EdgeInsets.zero,
      trailing: const Icon(Icons.chevron_right, color: Colors.transparent),
      leading: const SizedBox.shrink(),
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
