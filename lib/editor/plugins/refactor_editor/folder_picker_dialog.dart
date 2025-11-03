// =========================================
// NEW FILE: lib/editor/plugins/refactor_editor/folder_picker_dialog.dart
// =========================================

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import '../../../app/app_notifier.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../project/services/project_hierarchy_service.dart';

class FolderPickerDialog extends ConsumerStatefulWidget {
  const FolderPickerDialog({super.key});

  @override
  ConsumerState<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<FolderPickerDialog> {
  late String _currentPathUri;
  String? _selectedFolderPath;

  @override
  void initState() {
    super.initState();
    _currentPathUri =
        ref.read(appNotifierProvider).value?.currentProject?.rootUri ?? '';
    _selectedFolderPath = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentPathUri.isNotEmpty) {
        ref
            .read(projectHierarchyServiceProvider.notifier)
            .loadDirectory(_currentPathUri);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPathUri.isEmpty) {
      return const AlertDialog(
        content: Center(child: Text('No project open.')),
      );
    }

    final directoryState = ref.watch(
      directoryContentsProvider(_currentPathUri),
    );
    final fileHandler = ref.read(projectRepositoryProvider)!.fileHandler;
    final projectRootUri =
        ref.read(appNotifierProvider).value!.currentProject!.rootUri;

    return AlertDialog(
      title: const Text('Select a Folder to Ignore'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            _buildPathNavigator(projectRootUri, fileHandler),
            const Divider(),
            Expanded(
              child:
                  directoryState == null
                      ? const Center(child: CircularProgressIndicator())
                      : directoryState.when(
                        data: (nodes) => _buildDirectoryList(nodes),
                        loading:
                            () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                        error:
                            (err, stack) => Center(child: Text('Error: $err')),
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
          onPressed:
              _selectedFolderPath != null
                  ? () => Navigator.of(context).pop(_selectedFolderPath)
                  : null,
          child: const Text('Select'),
        ),
      ],
    );
  }

  Widget _buildDirectoryList(List<FileTreeNode> nodes) {
    final fileHandler = ref.read(projectRepositoryProvider)!.fileHandler;
    final projectRootUri =
        ref.read(appNotifierProvider).value!.currentProject!.rootUri;

    final directories = nodes.where((n) => n.file.isDirectory).toList();

    return ListView.builder(
      itemCount: directories.length,
      itemBuilder: (context, index) {
        final dirNode = directories[index];
        final dir = dirNode.file;
        final relativePath = fileHandler.getPathForDisplay(
          dir.uri,
          relativeTo: projectRootUri,
        );
        final isSelected = _selectedFolderPath == relativePath;

        return ListTile(
          leading: Icon(isSelected ? Icons.check_box : Icons.folder_outlined),
          title: Text(dir.name),
          selected: isSelected,
          onTap: () {
            ref
                .read(projectHierarchyServiceProvider.notifier)
                .loadDirectory(dir.uri);
            setState(() => _currentPathUri = dir.uri);
          },
          onLongPress: () {
            setState(() {
              if (isSelected) {
                _selectedFolderPath = null;
              } else {
                _selectedFolderPath = relativePath;
              }
            });
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
          onPressed:
              _currentPathUri == projectRootUri
                  ? null
                  : () {
                    final newPath = fileHandler.getParentUri(_currentPathUri);
                    ref
                        .read(projectHierarchyServiceProvider.notifier)
                        .loadDirectory(newPath);
                    setState(() => _currentPathUri = newPath);
                  },
        ),
        Expanded(
          child: Text(
            fileHandler
                    .getPathForDisplay(
                      _currentPathUri,
                      relativeTo: projectRootUri,
                    )
                    .isEmpty
                ? '/'
                : fileHandler.getPathForDisplay(
                  _currentPathUri,
                  relativeTo: projectRootUri,
                ),
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
