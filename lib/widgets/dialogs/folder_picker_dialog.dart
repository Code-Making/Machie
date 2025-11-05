// lib/editor/plugins/refactor_editor/folder_picker_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/repositories/project_repository.dart';
import '../../project/services/project_hierarchy_service.dart';
import '../../data/file_handler/file_handler.dart';
import '../file_list_view.dart'; // Import for FileTypeIcon

// RENAMED: The dialog is now more generic.
class FileOrFolderPickerDialog extends ConsumerStatefulWidget {
  const FileOrFolderPickerDialog({super.key});

  @override
  ConsumerState<FileOrFolderPickerDialog> createState() => _FileOrFolderPickerDialogState();
}

class _FileOrFolderPickerDialogState extends ConsumerState<FileOrFolderPickerDialog> {
  late String _currentPathUri;
  String? _selectedPath; // Can now be a file or a folder path.

  @override
  void initState() {
    super.initState();
    _currentPathUri = ref.read(appNotifierProvider).value?.currentProject?.rootUri ?? '';
    _selectedPath = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentPathUri.isNotEmpty) {
        ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(_currentPathUri);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPathUri.isEmpty) {
      return const AlertDialog(content: Center(child: Text('No project open.')));
    }

    final directoryState = ref.watch(directoryContentsProvider(_currentPathUri));
    final fileHandler = ref.read(projectRepositoryProvider)!.fileHandler;
    final projectRootUri = ref.read(appNotifierProvider).value!.currentProject!.rootUri;

    return AlertDialog(
      title: const Text('Select a File or Folder'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            _buildPathNavigator(projectRootUri, fileHandler),
            const Divider(),
            Expanded(
              child: directoryState == null
                  ? const Center(child: CircularProgressIndicator())
                  : directoryState.when(
                      data: (nodes) => _buildDirectoryList(nodes),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Center(child: Text('Error: $err')),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedPath != null
              ? () => Navigator.of(context).pop(_selectedPath)
              : null,
          child: const Text('Select'),
        ),
      ],
    );
  }

  Widget _buildDirectoryList(List<FileTreeNode> nodes) {
    final fileHandler = ref.read(projectRepositoryProvider)!.fileHandler;
    final projectRootUri = ref.read(appNotifierProvider).value!.currentProject!.rootUri;
    
    // UPDATED: Now we show both files and folders.
    final items = nodes.map((n) => n.file).toList();
    
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final relativePath = fileHandler.getPathForDisplay(item.uri, relativeTo: projectRootUri);
        final isSelected = _selectedPath == relativePath;

        return ListTile(
          // UPDATED: Use the FileTypeIcon and appropriate selection icon.
          leading: isSelected ? const Icon(Icons.check_box) : FileTypeIcon(file: item),
          title: Text(item.name),
          selected: isSelected,
          onTap: () {
            if (item.isDirectory) {
              // Tapping a directory navigates into it.
              ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(item.uri);
              setState(() => _currentPathUri = item.uri);
            } else {
              // Tapping a file selects it.
              setState(() {
                if (isSelected) {
                  _selectedPath = null;
                } else {
                  _selectedPath = relativePath;
                }
              });
            }
          },
          // Long pressing a directory now selects it.
          onLongPress: () {
            if (item.isDirectory) {
               setState(() {
                if (isSelected) {
                  _selectedPath = null;
                } else {
                  _selectedPath = relativePath;
                }
              });
            }
          },
        );
      },
    );
  }

  Widget _buildPathNavigator(String projectRootUri, FileHandler fileHandler) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_upward),
          onPressed: _currentPathUri == projectRootUri
              ? null
              : () {
                  final newPath = fileHandler.getParentUri(_currentPathUri);
                  ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(newPath);
                  setState(() => _currentPathUri = newPath);
                },
        ),
        Expanded(
          child: Text(
            fileHandler.getPathForDisplay(_currentPathUri, relativeTo: projectRootUri).isEmpty
                ? '/'
                : fileHandler.getPathForDisplay(_currentPathUri, relativeTo: projectRootUri),
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}