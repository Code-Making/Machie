import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../file_system/file_handler.dart';
import '../session/session_management.dart';
import '../plugins/plugin_architecture.dart';
import '../plugins/plugin_registry.dart'; // For EditorPlugin, activePluginsProvider


final rootUriProvider = StateProvider<DocumentFile?>((_) => null);

final directoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String?>((ref, uri) async {
      final handler = ref.read(fileHandlerProvider);
      final targetUri = uri ?? await handler.getPersistedRootUri();
      return targetUri != null ? handler.listDirectory(targetUri) : [];
    });

class UnsupportedFileType implements Exception {
  final String uri;
  UnsupportedFileType(this.uri);

  @override
  String toString() => 'Unsupported file type: $uri';
}

class PluginSelectionDialog extends StatelessWidget {
  final List<EditorPlugin> plugins;

  const PluginSelectionDialog({super.key, required this.plugins});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open With'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: plugins.map((plugin) {
            return ListTile(
              leading: _getPluginIcon(plugin),
              title: Text(_getPluginName(plugin)),
              onTap: () => Navigator.pop(context, plugin),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _getPluginName(EditorPlugin plugin) {
    // Implement logic to get plugin display name
    return plugin.runtimeType.toString().replaceAll('Plugin', '');
  }

  Widget _getPluginIcon(EditorPlugin plugin) {
    // Implement logic to get plugin icon
    return plugin.icon ?? const Icon(Icons.extension); // Default icon
  }
}

class FileExplorerDrawer extends ConsumerWidget {
  final DocumentFile? currentDir;

  const FileExplorerDrawer({super.key, this.currentDir});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: Column(
        children: [
          // Header with title and close
          AppBar(
            title: const Text('File Explorer'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          // File operations header
          _FileOperationsHeader(),

          // Directory tree
          Expanded(
            child:
                currentDir == null
                    ? const Center(child: Text('No folder open'))
                    : _DirectoryView(
                      directory: currentDir!,
                      // Update the onOpenFile callback in FileExplorerDrawer's build method
                        onOpenFile: (file) async {
                          final plugins = ref.read(pluginRegistryProvider);
                          final supportedPlugins = plugins.where((p) => p.supportsFile(file)).toList();
                        
                          if (supportedPlugins.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No available plugins support ${file.name}')),
                            );
                            return;
                          }
                        
                          if (supportedPlugins.length == 1) {
                            ref.read(sessionProvider.notifier).openFile(file, plugin:supportedPlugins.first);
                          } else {
                            final selectedPlugin = await showDialog<EditorPlugin>(
                              context: context,
                              builder: (context) => PluginSelectionDialog(plugins: supportedPlugins),
                            );
                            if (selectedPlugin != null) {
                              ref.read(sessionProvider.notifier).openFile(file, plugin: selectedPlugin);
                            }
                          }
                          Navigator.pop(context);
                        },
                    ),
          ),

          // Footer for additional operations
          _FileOperationsFooter(),
        ],
      ),
    );
  }
}

class _FileOperationsHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ButtonBar(
        alignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Folder'),
            onPressed: () async {
              final pickedDir =
                  await ref.read(fileHandlerProvider).pickDirectory();
              if (pickedDir != null) {
                ref.read(rootUriProvider.notifier).state = pickedDir;
                ref.read(sessionProvider.notifier).changeDirectory(pickedDir);
                Navigator.pop(context);
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.file_open),
            label: const Text('Open File'),
            onPressed: () async {
              final pickedFile = await ref.read(fileHandlerProvider).pickFile();
              if (pickedFile != null) {
                ref.read(sessionProvider.notifier).openFile(pickedFile);
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _FileOperationsFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: ButtonBar(
        children: [
          /* Add other operations here like:
          TextButton(
            child: Text('New Folder'),
            onPressed: () {},
          ),
          TextButton(
            child: Text('Upload File'),
            onPressed: () {},
          ),*/
        ],
      ),
    );
  }
}

class _DirectoryView extends ConsumerWidget {
  final DocumentFile directory;
  final Function(DocumentFile) onOpenFile;
  final int depth;

  const _DirectoryView({
    required this.directory,
    required this.onOpenFile,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(directoryContentsProvider(directory.uri));

    return contentsAsync.when(
      loading: () => _buildLoadingState(),
      error: (error, _) => _buildErrorState(),
      data: (contents) => _buildDirectoryList(contents),
    );
  }

  Widget _buildDirectoryList(List<DocumentFile> contents) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: contents.length,
      itemBuilder:
          (context, index) => _DirectoryItem(
            item: contents[index],
            onOpenFile: onOpenFile,
            depth: depth,
          ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      shrinkWrap: true,
      children: [_DirectoryLoadingTile(depth: depth)],
    );
  }

  Widget _buildErrorState() {
    return ListView(
      shrinkWrap: true,
      children: const [
        ListTile(
          leading: Icon(Icons.error, color: Colors.red),
          title: Text('Error loading directory'),
        ),
      ],
    );
  }
}

class _DirectoryItem extends StatelessWidget {
  final DocumentFile item;
  final Function(DocumentFile) onOpenFile;
  final int depth;

  const _DirectoryItem({
    required this.item,
    required this.onOpenFile,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    if (item.isDirectory) {
      return _DirectoryExpansionTile(
        file: item,
        depth: depth,
        onOpenFile: onOpenFile,
      );
    }
    return _FileItem(file: item, depth: depth, onTap: () => onOpenFile(item));
  }
}

class _DirectoryExpansionTile extends ConsumerStatefulWidget {
  final DocumentFile file;
  final int depth;
  final Function(DocumentFile) onOpenFile;

  const _DirectoryExpansionTile({
    required this.file,
    required this.depth,
    required this.onOpenFile,
  });

  @override
  ConsumerState<_DirectoryExpansionTile> createState() =>
      _DirectoryExpansionTileState();
}

class _DirectoryExpansionTileState
    extends ConsumerState<_DirectoryExpansionTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(
        _isExpanded ? Icons.folder_open : Icons.folder,
        color: Colors.yellow,
      ),
      title: Text(widget.file.name),
      childrenPadding: EdgeInsets.only(left: (widget.depth + 1) * 16.0),
      onExpansionChanged: (expanded) => setState(() => _isExpanded = expanded),
      children: [
        _DirectoryView(
          directory: widget.file,
          onOpenFile: widget.onOpenFile,
          depth: widget.depth + 1,
        ),
      ],
    );
  }
}

class _FileItem extends StatelessWidget {
  final DocumentFile file;
  final int depth;
  final VoidCallback onTap;

  const _FileItem({
    required this.file,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
      leading: const Icon(Icons.insert_drive_file),
      title: Text(file.name),
      onTap: onTap,
    );
  }
}

class _DirectoryLoadingTile extends StatelessWidget {
  final int depth;

  const _DirectoryLoadingTile({required this.depth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: (depth + 1) * 16.0),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}