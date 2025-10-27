// lib/widgets/file_list_view.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/plugin_registry.dart';
import 'package:machine/data/file_handler/file_handler.dart';

// (FileTypeIcon is unchanged)
class FileTypeIcon extends ConsumerWidget {
  final DocumentFile file;
  const FileTypeIcon({super.key, required this.file});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (file.isDirectory) {
      return Icon(Icons.folder, color: Colors.yellow.shade700);
    }
    final plugins = ref.watch(activePluginsProvider);
    final plugin = plugins.firstWhereOrNull((p) => p.supportsFile(file));
    return plugin?.icon ?? const Icon(Icons.article_outlined);
  }
}

/// A typedef for the builder function that allows decorating list items.
typedef FileListItemBuilder = Widget Function(
  BuildContext context,
  DocumentFile item,
  int depth,
  Widget defaultItem,
);

/// The core, stateless, reusable widget for displaying a list of files.
class FileListView extends StatelessWidget {
  final List<DocumentFile> items;
  final Set<String> expandedDirectoryUris;
  final int depth;
  final void Function(DocumentFile file) onFileTapped;
  final void Function(DocumentFile directory, bool isExpanded) onExpansionChanged;
  final Widget Function(DocumentFile directory) directoryChildrenBuilder;
  // NEW: Optional builder for decoration
  final FileListItemBuilder? itemBuilder;

  const FileListView({
    super.key,
    required this.items,
    required this.expandedDirectoryUris,
    required this.onFileTapped,
    required this.onExpansionChanged,
    required this.directoryChildrenBuilder,
    this.itemBuilder, // Make it optional
    this.depth = 1,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: PageStorageKey(items.map((e) => e.uri).join()),
      padding: const EdgeInsets.only(top: 8.0),
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        // Build the default widget based on type
        final Widget defaultItem;
        if (item.isDirectory) {
          defaultItem = _DirectoryItem(
            directory: item,
            depth: depth,
            isExpanded: expandedDirectoryUris.contains(item.uri),
            onExpansionChanged: (isExpanded) => onExpansionChanged(item, isExpanded),
            children: [directoryChildrenBuilder(item)],
          );
        } else {
          defaultItem = FileItem(
            file: item,
            depth: depth,
            onTapped: () => onFileTapped(item),
          );
        }

        // If an itemBuilder is provided, use it to wrap the default widget.
        // Otherwise, just return the default widget.
        if (itemBuilder != null) {
          return itemBuilder!(context, item, depth, defaultItem);
        }
        return defaultItem;
      },
    );
  }
}

// (FileItem and _DirectoryItem implementations are unchanged and remain private)
class FileItem extends StatelessWidget {
  final DocumentFile file;
  final int depth;
  final VoidCallback onTapped;
  final String? subtitle; // ADDED: Optional subtitle

  const FileItem({
    super.key,
    required this.file,
    required this.depth,
    required this.onTapped,
    this.subtitle, // ADDED
  });

  static const double _kIndentPerLevel = 16.0;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTapped,
      dense: true,
      contentPadding: EdgeInsets.only(left: depth * _kIndentPerLevel, right: 8.0),
      leading: FileTypeIcon(file: file),
      title: Text(
        file.name,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.0),
      ),
      // ADDED: Conditionally display the subtitle
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.0),
            )
          : null,
    );
  }
}

class _DirectoryItem extends StatelessWidget {
  final DocumentFile directory;
  final int depth;
  final bool isExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final List<Widget> children;
  const _DirectoryItem({required this.directory, required this.depth, required this.isExpanded, required this.onExpansionChanged, required this.children});
  static const double _kIndentPerLevel = 16.0;
  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: PageStorageKey<String>(directory.uri),
      tilePadding: EdgeInsets.only(left: depth * _kIndentPerLevel, right: 8.0),
      leading: Icon(isExpanded ? Icons.folder_open : Icons.folder, color: Colors.yellow.shade700),
      title: Text(directory.name, style: const TextStyle(fontSize: 14.0)),
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: isExpanded,
      onExpansionChanged: onExpansionChanged,
      children: children,
    );
  }
}