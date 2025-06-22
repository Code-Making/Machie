// lib/explorer/common/save_as_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_notifier.dart';
import '../../data/repositories/project_repository.dart'; // NEW IMPORT

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
    
    // REFACTOR: Lazily load the initial directory contents.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentPathUri.isNotEmpty) {
        ref.read(projectHierarchyProvider)?.loadDirectory(_currentPathUri);
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
    
    // REFACTOR: Watch the hierarchy cache instead of the old FutureProvider.
    final directoryContents = ref.watch(
      projectHierarchyProvider.select((p) => p?.state[_currentPathUri]),
    );

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
              // REFACTOR: Handle the loading state explicitly.
              child: directoryContents == null
                  ? const Center(child: CircularProgressIndicator())
                  : _buildDirectoryList(directoryContents),
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

  Widget _buildDirectoryList(List<dynamic> files) {
    final directories = files.where((f) => f.isDirectory).toList();
    return ListView.builder(
      itemCount: directories.length,
      itemBuilder: (context, index) {
        final dir = directories[index];
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(dir.name),
          onTap: () {
            // REFACTOR: Trigger a lazy load for the new directory.
            ref.read(projectHierarchyProvider)?.loadDirectory(dir.uri);
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

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_upward),
          onPressed: _currentPathUri == projectRootUri
              ? null
              : () {
                  final segments = _currentPathUri.split('%2F');
                  final newPath =
                      segments.sublist(0, segments.length - 1).join('%2F');
                  // REFACTOR: Trigger lazy load for the parent directory.
                  ref.read(projectHierarchyProvider)?.loadDirectory(newPath);
                  setState(() {
                    _currentPathUri = newPath;
                  });
                },
        ),
        Expanded(
          child: Text(
            Uri.decodeComponent(
              _currentPathUri
                  .split('/')
                  .lastWhere((s) => s.isNotEmpty, orElse: () => 'Project Root'),
            ),
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}