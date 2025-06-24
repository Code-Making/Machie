// lib/explorer/common/file_explorer_widgets.dart
import 'package:collection/collection.dart';
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

// All changes are made within the DirectoryItem widget.
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

  // --- STYLING CONSTANTS ---
  static const double _kBaseIndent = 16.0;
  static const double _kFontSize = 14.0;
  static const double _kVerticalPadding = 2.0; // Small vertical padding

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final explorerNotifier = ref.read(activeExplorerNotifierProvider);
    
    // Calculate the indentation for the current item.
    final double currentIndent = depth * _kBaseIndent;

    Widget childWidget;
    if (item.isDirectory) {
      childWidget = ExpansionTile(
        key: PageStorageKey<String>(item.uri),
        // Set custom padding for compactness and indentation.
        tilePadding: EdgeInsets.only(
          left: currentIndent,
          right: 8.0,
          top: _kVerticalPadding,
          bottom: _kVerticalPadding,
        ),
        // Remove extra padding from the children, as they will calculate their own.
        childrenPadding: EdgeInsets.zero,
        leading: Icon(
          isExpanded ? Icons.folder_open : Icons.folder,
          color: Colors.yellow.shade700,
        ),
        // Apply the desired font size.
        title: Text(
          item.name,
          style: const TextStyle(fontSize: _kFontSize),
        ),
        subtitle: subtitle != null
            ? Text(subtitle!, style: const TextStyle(fontSize: _kFontSize - 2))
            : null,
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          if (expanded) {
            ref.read(projectHierarchyProvider.notifier).loadDirectory(item.uri);
          }
          explorerNotifier.updateSettings((settings) {
            final currentSettings = settings as FileExplorerSettings;
            final newExpanded = Set<String>.from(currentSettings.expandedFolders);
            if (expanded) {
              newExpanded.add(item.uri);
            } else {
              newExpanded.remove(item.uri);
            }
            return currentSettings.copyWith(expandedFolders: newExpanded);
          });
        },
        children: [
          if (isExpanded)
            Consumer(
              builder: (context, ref, _) {
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
      childWidget = ListTile(
        key: ValueKey(item.uri),
        // Use dense property for a generally more compact layout.
        dense: true,
        // Set custom padding. The indent for a file is its parent's indent plus one level.
        contentPadding: EdgeInsets.only(
          left: currentIndent + _kBaseIndent,
          top: _kVerticalPadding,
          bottom: _kVerticalPadding,
        ),
        leading: FileTypeIcon(file: item),
        // Apply the desired font size.
        title: Text(
          item.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: _kFontSize),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: _kFontSize - 2),
              )
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