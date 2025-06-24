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

// REFACTORED: The provider now holds the file being dragged, or null.
// This is much more powerful than a simple boolean.
final draggedFileProvider = StateProvider<DocumentFile?>((ref) => null);

// _isDropAllowed helper function is unchanged and remains correct.
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

    // The ListView no longer needs to be a DragTarget itself.
    // Drops will be handled by individual DirectoryItems or the new RootDropZone.
    return ListView.builder(
      key: PageStorageKey(widget.directory),
      // Add padding to make space for the root drop zone.
      padding: const EdgeInsets.only(top: 8.0),
      shrinkWrap: true,
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

// REFACTORED: The RootDropZone is now much smarter.
class RootDropZone extends ConsumerWidget {
  final String projectRootUri;
  const RootDropZone({super.key, required this.projectRootUri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the new provider to get the actual file being dragged.
    final draggedFile = ref.watch(draggedFileProvider);

    // Condition 1: Don't show if nothing is being dragged.
    if (draggedFile == null) {
      return const SizedBox.shrink();
    }

    // Condition 2: Don't show if the dragged file is ALREADY in the root.
    final parentUri = draggedFile.uri.substring(0, draggedFile.uri.lastIndexOf('%2F'));
    if (parentUri == projectRootUri) {
      return const SizedBox.shrink();
    }
    
    // The rest of the logic remains, but it's now only active when appropriate.
    return DragTarget<DocumentFile>(
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        final canAccept = isHovered && _isDropAllowed(draggedFile, RootPlaceholder(projectRootUri));

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: canAccept 
                ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                : Theme.of(context).colorScheme.error.withOpacity(0.2),
            border: Border.all(
              color: canAccept 
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.move_up, /* ... */),
              const SizedBox(width: 8),
              Text('Move to Project Root', /* ... */),
            ],
          ),
        );
      },
      onWillAccept: (data) => data != null && _isDropAllowed(data, RootPlaceholder(projectRootUri)),
      onAccept: (file) {
        ref.read(explorerServiceProvider).moveItem(file, RootPlaceholder(projectRootUri));
      },
    );
  }
}

// REFACTORED: DirectoryItem now uses the new provider.
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
        // Set the provider state to the file being dragged.
        ref.read(draggedFileProvider.notifier).state = widget.item;
      },
      onDragEnd: (details) {
        // Always reset the dragging state to null when the drag ends.
        ref.read(draggedFileProvider.notifier).state = null;
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
          // Watch the new provider. isDragging is now just checking for non-null.
          final isDragging = ref.watch(draggedFileProvider) != null;
          final isHovered = candidateData.isNotEmpty;
          
          Color? backgroundColor;
          if (isHovered && _isDropAllowed(candidateData.first!, widget.item)) {
            backgroundColor = Theme.of(context).colorScheme.primary.withOpacity(0.4);
          } else if (isDragging) {
            backgroundColor = Theme.of(context).colorScheme.primary.withOpacity(0.1);
          }
          
          return Container(
            color: backgroundColor,
            child: childWidget,
          );
        },
        onWillAccept: (draggedData) => draggedData != null && _isDropAllowed(draggedData, widget.item),
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