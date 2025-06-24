// lib/explorer/common/file_explorer_widgets.dart
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../editor/plugins/plugin_registry.dart';
import '../plugins/file_explorer/file_explorer_state.dart';
import 'file_explorer_commands.dart';
import 'file_explorer_dialogs.dart';
import '../../utils/toast.dart';
import '../../editor/services/editor_service.dart';
import '../explorer_plugin_registry.dart';
import '../services/explorer_service.dart';

final isDraggingFileProvider = StateProvider<bool>((ref) => false);

bool _isDropAllowed(DocumentFile draggedFile, DocumentFile targetFolder) {
  if (draggedFile.uri == targetFolder.uri) return false;
  if (targetFolder.uri.startsWith(draggedFile.uri)) return false;
  final parentUri = draggedFile.uri.substring(0, draggedFile.uri.lastIndexOf('%2F'));
  if (parentUri == targetFolder.uri) return false;
  return true;
}

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
          ref.read(projectHierarchyProvider.notifier).loadDirectory(widget.directory);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final directoryContents = ref.watch(projectHierarchyProvider)[widget.directory];

    if (directoryContents == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(8.0),
        child: CircularProgressIndicator(),
      ));
    }
    
    final sortedContents = List<DocumentFile>.from(directoryContents);
    _applySorting(sortedContents, widget.state.viewMode);

    final listView = ListView.builder(
      key: PageStorageKey(widget.directory),
      shrinkWrap: true,
      // Use ClampingScrollPhysics to prevent the ListView from showing an overscroll
      // glow, which would cover the drop target highlight.
      physics: const ClampingScrollPhysics(),
      itemCount: sortedContents.length,
      itemBuilder: (context, index) {
        final item = sortedContents[index];
        final depth =
            item.uri.split('%2F').length - widget.projectRootUri.split('%2F').length;
        return DirectoryItem(
          item: item,
          depth: depth,
          isExpanded: widget.state.expandedFolders.contains(item.uri),
        );
      },
    );
    
    // FIX: Use a Stack to ensure the root drop target is only for "empty" space.
    return DragTarget<DocumentFile>(
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return Stack(
          // Allow children to be drawn outside the bounds of the Stack.
          clipBehavior: Clip.none,
          children: [
            // Layer 1: The background drop zone highlight.
            // It's only visible when an item is hovering over the empty space.
            if (isHovered)
              Container(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              ),
            // Layer 2: The actual list of files and folders.
            // Because it's on top, it will capture all pointer events for its items,
            // preventing the underlying DragTarget from firing for them.
            listView,
          ],
        );
      },
      onWillAccept: (draggedData) {
        if (draggedData == null) return false;
        return _isDropAllowed(draggedData, RootPlaceholder(widget.directory));
      },
      onAccept: (draggedFile) {
        ref.read(explorerServiceProvider).moveItem(draggedFile, RootPlaceholder(widget.directory));
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

// DirectoryItem is now correct from the previous step and does not need changes.
class DirectoryItem extends ConsumerStatefulWidget {
  final DocumentFile item;
  final int depth;
  final bool isExpanded;
  final String? subtitle;
  const DirectoryItem({ super.key, required this.item, required this.depth, required this.isExpanded, this.subtitle, });
  @override
  ConsumerState<DirectoryItem> createState() => _DirectoryItemState();
}
class _DirectoryItemState extends ConsumerState<DirectoryItem> {
  static const double _kBaseIndent = 16.0;
  static const double _kFontSize = 14.0;
  static const double _kVerticalPadding = 2.0;
  
  @override
  Widget build(BuildContext context) {
    final itemContent = _buildItemContent();
    return LongPressDraggable<DocumentFile>(
      data: widget.item,
      feedback: _buildDragFeedback(),
      childWhenDragging: Opacity(opacity: 0.5, child: itemContent),
      delay: const Duration(seconds: 1),
      onDragStarted: () {
        ref.read(isDraggingFileProvider.notifier).state = true;
      },
      onDragEnd: (details) {
        ref.read(isDraggingFileProvider.notifier).state = false;
        if (!details.wasAccepted) {
          showFileContextMenu(context, ref, widget.item);
        }
      },
      child: GestureDetector(
        onTap: widget.item.isDirectory ? null : () async {
          final success = await ref.read(appNotifierProvider.notifier).openFileInEditor(widget.item);
          if (success && mounted) {
            Navigator.of(context).pop();
          }
        },
        child: itemContent,
      ),
    );
  }
  
  Widget _buildItemContent() {
    Widget childWidget = widget.item.isDirectory
        ? _buildDirectoryTile()
        : _buildFileTile();
    
    if (widget.item.isDirectory) {
      return DragTarget<DocumentFile>(
        builder: (context, candidateData, rejectedData) {
          final bool isDragging = ref.watch(isDraggingFileProvider);
          final bool isHovered = candidateData.isNotEmpty;
          
          Color? backgroundColor;
          if (isHovered) {
            backgroundColor = Theme.of(context).colorScheme.primary.withOpacity(0.4);
          } else if (isDragging) {
            backgroundColor = Theme.of(context).colorScheme.primary.withOpacity(0.1);
          }
          
          return Container(
            color: backgroundColor,
            child: childWidget,
          );
        },
        onWillAccept: (draggedData) {
          if (draggedData == null) return false;
          return _isDropAllowed(draggedData, widget.item);
        },
        onAccept: (draggedFile) {
          ref.read(explorerServiceProvider).moveItem(draggedFile, widget.item);
        },
      );
    }
    return childWidget;
  }
  
  Widget _buildFileTile() {
    final double currentIndent = widget.depth * _kBaseIndent;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(
        left: currentIndent + _kBaseIndent,
        top: _kVerticalPadding,
        bottom: _kVerticalPadding,
      ),
      leading: FileTypeIcon(file: widget.item),
      title: Text(widget.item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: _kFontSize)),
      subtitle: widget.subtitle != null
          ? Text(widget.subtitle!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: _kFontSize - 2))
          : null,
    );
  }
  
  Widget _buildDirectoryTile() {
    final double currentIndent = widget.depth * _kBaseIndent;
    return ExpansionTile(
      key: PageStorageKey<String>(widget.item.uri),
      tilePadding: EdgeInsets.only(
        left: currentIndent,
        right: 8.0,
        top: _kVerticalPadding,
        bottom: _kVerticalPadding,
      ),
      childrenPadding: EdgeInsets.zero,
      leading: Icon(
        widget.isExpanded ? Icons.folder_open : Icons.folder,
        color: Colors.yellow.shade700,
      ),
      title: Text(widget.item.name, style: const TextStyle(fontSize: _kFontSize)),
      subtitle: widget.subtitle != null
          ? Text(widget.subtitle!, style: const TextStyle(fontSize: _kFontSize - 2))
          : null,
      initiallyExpanded: widget.isExpanded,
      onExpansionChanged: (expanded) {
        if (expanded) {
          ref.read(projectHierarchyProvider.notifier).loadDirectory(widget.item.uri);
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
              final currentState = ref.watch(activeExplorerSettingsProvider) as FileExplorerSettings?;
              final project = ref.watch(appNotifierProvider).value!.currentProject!;
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
      color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
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