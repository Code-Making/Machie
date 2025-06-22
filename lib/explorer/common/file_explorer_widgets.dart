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
import 'file_explorer_dialogs.dart';
import '../../utils/toast.dart';
import '../../editor/services/editor_service.dart';
import '../explorer_plugin_registry.dart';

// REFACTOR: The DirectoryView is now purely declarative.
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
    // Trigger the initial lazy load if needed.
    // We do this in initState to ensure it's called only once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final hierarchy = ref.read(projectHierarchyProvider);
        if (hierarchy?.state[widget.directory] == null) {
          hierarchy?.loadDirectory(widget.directory);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch the hierarchy provider and select only the contents of this directory.
    final contents = ref.watch(
      projectHierarchyProvider.select((cache) => cache?.state[widget.directory]),
    );

    // If contents are null, it means they are loading for the first time.
    if (contents == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(8.0),
        child: CircularProgressIndicator(),
      ));
    }
    
    // Create a mutable copy for sorting
    final sortedContents = List<DocumentFile>.from(contents);
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

// ... (DirectoryItem and other widgets are mostly unchanged but benefit from the new system)
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
          // This part remains the same, but it now controls the expansion
          // state used by the already-loaded or soon-to-be-loaded DirectoryView.
          if (expanded) {
            ref.read(projectHierarchyProvider)?.loadDirectory(item.uri);
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
        childrenPadding: EdgeInsets.only(left: (depth > 0 ? 16.0 : 0)),
        children: [
          // The isExpanded check ensures the child DirectoryView is only in the
          // widget tree when needed, allowing its initState to trigger the lazy load.
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
        contentPadding: EdgeInsets.only(left: (depth) * 16.0 + 16.0),
        leading: FileTypeIcon(file: item),
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        subtitle:
            subtitle != null ? Text(subtitle!, overflow: TextOverflow.ellipsis) : null,
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