// lib/explorer/common/file_explorer_widgets.dart
import 'dart:async'; // NEW IMPORT for Timer
import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart'; // NEW IMPORT for DragUpdateDetails
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

// DirectoryView is unchanged.
// DirectoryView remains unchanged as it just passes data down.
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

    return ListView.builder(
      key: PageStorageKey(widget.directory),
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

// REFACTORED: This widget now uses LongPressDraggable and a custom gesture detector.
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
  // --- STATE for Gesture Handling ---
  Timer? _longPressTimer;
  bool _isDragStarted = false;

  // --- STYLING CONSTANTS ---
  static const double _kBaseIndent = 16.0;
  static const double _kFontSize = 14.0;
  static const double _kVerticalPadding = 2.0;
  
  void _startLongPressTimer(BuildContext context) {
    // If a drag hasn't started after 300ms, show the context menu.
    _longPressTimer = Timer(const Duration(milliseconds: 300), () {
      if (!_isDragStarted) {
        showFileContextMenu(context, ref, widget.item);
      }
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
  }
  
  @override
  void dispose() {
    _cancelLongPressTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemContent = _buildItemContent(context);

    // Use LongPressDraggable for delayed dragging that doesn't conflict with scrolling.
    return LongPressDraggable<DocumentFile>(
      data: widget.item,
      feedback: _buildDragFeedback(context),
      childWhenDragging: Opacity(opacity: 0.5, child: itemContent),
      // Delay before a drag starts. This allows for scrolling.
      delay: const Duration(milliseconds: 200),
      onDragStarted: () {
        _isDragStarted = true;
        _cancelLongPressTimer(); // A drag has started, so don't show the menu.
        ref.read(isDraggingFileProvider.notifier).state = true;
      },
      onDragEnd: (details) {
        ref.read(isDraggingFileProvider.notifier).state = false;
        _isDragStarted = false;
      },
      // The actual widget shown in the list.
      // We wrap it in a GestureDetector to handle taps and the initial long press.
      child: GestureDetector(
        // This makes the entire row tappable, not just the text.
        behavior: HitTestBehavior.opaque,
        onTap: widget.item.isDirectory ? null : () async {
          final success = await ref.read(appNotifierProvider.notifier).openFileInEditor(widget.item);
          if (success && mounted) {
            Navigator.of(context).pop();
          }
        },
        // Start the timer when the user presses and holds.
        onLongPressStart: (_) => _startLongPressTimer(context),
        // If the user lifts their finger, cancel the timer.
        onLongPressEnd: (_) => _cancelLongPressTimer(),
        // If the user moves their finger while holding, it's a drag, so cancel.
        onLongPressMoveUpdate: (_) => _cancelLongPressTimer(),
        child: itemContent,
      ),
    );
  }
  
  Widget _buildItemContent(BuildContext context) {
    // ... This method is now simplified as it doesn't need its own GestureDetector ...
    // ... It now correctly uses `widget.` to access properties ...

    Widget childWidget;

    if (widget.item.isDirectory) {
      childWidget = _buildDirectoryTile(context);
    } else {
      childWidget = _buildFileTile(context);
    }
    
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
          if (draggedData.uri == widget.item.uri) return false;
          if (widget.item.uri.startsWith(draggedData.uri)) return false;
          return true;
        },
        onAccept: (draggedFile) {
          ref.read(explorerServiceProvider).moveItem(draggedFile, widget.item);
        },
      );
    }

    return childWidget;
  }
  
  Widget _buildFileTile(BuildContext context) {
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
  
  Widget _buildDirectoryTile(BuildContext context) {
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

  Widget _buildDragFeedback(BuildContext context) {
    return Material(
      elevation: 4.0,
      color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        child: ListTile(
          leading: FileTypeIcon(file: item),
          title: Text(
            item.name,
            style: const TextStyle(fontSize: _kFontSize, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

// RootPlaceholder and FileTypeIcon are unchanged
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