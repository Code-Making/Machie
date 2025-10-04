// lib/explorer/common/save_as_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_notifier.dart';
import '../../data/repositories/project_repository.dart';
import '../../project/services/project_file_cache.dart'; // ADD IMPORT

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentPathUri.isNotEmpty) {
        // FIX: Call the method on the .notifier instance.
        ref
            .read(projectFileCacheProvider.notifier)
            .loadDirectory(_currentPathUri);
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

    // FIX: Watch the provider directly to get the state (the Map).
    // Then, access the specific directory's contents from the map.
    final directoryContents = ref.watch(projectFileCacheProvider
        .select((s) => s.directoryContents[_currentPathUri]));

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
              child:
                  directoryContents == null
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
        // UPDATED: Call the method on the new notifier.
        ref.read(projectFileCacheProvider.notifier).loadDirectory(dir.uri);
        setState(() { _currentPathUri = dir.uri; });
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
            // UPDATED: Call the method on the new notifier.
            ref.read(projectFileCacheProvider.notifier).loadDirectory(newPath);
            setState(() { _currentPathUri = newPath; });
          },
        ),
        Expanded(
          child: Text(
            // THE FIX: Use the fileHandler to get a display-friendly name.
            fileHandler.getFileName(fileHandler.getPathForDisplay(_currentPathUri)),
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
