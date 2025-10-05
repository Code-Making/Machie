import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_notifier.dart';
import '../../data/repositories/project_repository.dart';
import '../../project/services/project_hierarchy_service.dart';

class SaveAsDialogResult {
  final String parentUri;
  final String fileName;
  SaveAsDialogResult(this.parentUri, this.fileName);
}

class SaveAsDialog extends ConsumerStatefulWidget {
  final String initialFileName;
  const SaveAsDialog({super.key, required this.initialFileName});

  @override
  ConsumerState<SaveAsDialog> createState() => _SaveAsDialogState();
}

class _SaveAsDialogState extends ConsumerState<SaveAsDialog> {
  late String _currentPathUri;
  late final TextEditingController _fileNameController;

  @override
  void initState() {
    super.initState();
    _fileNameController = TextEditingController(text: widget.initialFileName);
    _currentPathUri =
        ref.read(appNotifierProvider).value?.currentProject?.rootUri ?? '';

    // Trigger the initial load for the root directory after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentPathUri.isNotEmpty) {
        ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(_currentPathUri);
      }
    });
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPathUri.isEmpty) {
      return const AlertDialog(
        title: Text('Save As...'),
        content: Center(child: CircularProgressIndicator()),
      );
    }

    // Watch the provider for the current path.
    final directoryState = ref.watch(directoryContentsProvider(_currentPathUri));

    return AlertDialog(
      title: const Text('Save As...'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            _buildPathNavigator(),
            const Divider(),
            Expanded(
              // --- THIS IS THE FIX ---
              // Use .when to handle the different states of the AsyncValue
              child: directoryState.when(
                data: (nodes) => _buildDirectoryList(nodes),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err')),
                // Handle the null state (before the first load is triggered)
                orElse: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
            const Divider(),
            TextField(
              controller: _fileNameController,
              decoration: const InputDecoration(labelText: 'File Name'),
              autofocus: true,
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
          onPressed: () {
            if (_fileNameController.text.trim().isNotEmpty) {
              Navigator.of(context).pop(
                SaveAsDialogResult(
                  _currentPathUri,
                  _fileNameController.text.trim(),
                ),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildDirectoryList(List<FileTreeNode> nodes) {
    final directories = nodes.where((n) => n.file.isDirectory).toList();
    return ListView.builder(
      itemCount: directories.length,
      itemBuilder: (context, index) {
        final dirNode = directories[index];
        final dir = dirNode.file;
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(dir.name),
          onTap: () {
            // Trigger a lazy-load for the new directory
            ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(dir.uri);
            setState(() {
              _currentPathUri = dir.uri;
            });
          },
        );
      },
    );
  }

  Widget _buildPathNavigator() {
    final projectRootUri =
        ref.read(appNotifierProvider).value?.currentProject?.rootUri ?? '';
    final fileHandler = ref.read(projectRepositoryProvider)?.fileHandler;
    if (fileHandler == null) return const SizedBox.shrink();

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_upward),
          onPressed:
              _currentPathUri == projectRootUri
                  ? null
                  : () {
                    final newPath = fileHandler.getParentUri(_currentPathUri);
                    // Trigger a lazy-load for the parent directory
                    ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(newPath);
                    setState(() {
                      _currentPathUri = newPath;
                    });
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