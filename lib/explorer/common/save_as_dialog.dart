// lib/explorer/common/save_as_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';

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
        ref.read(appNotifierProvider).value!.currentProject!.rootUri;
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final directoryContents = ref.watch(
      currentProjectDirectoryContentsProvider(_currentPathUri),
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
              child: directoryContents.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, st) => Center(child: Text('Error: $err')),
                data: (files) {
                  final directories =
                      files.where((f) => f.isDirectory).toList();
                  return ListView.builder(
                    itemCount: directories.length,
                    itemBuilder: (context, index) {
                      final dir = directories[index];
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(dir.name),
                        onTap: () {
                          setState(() {
                            _currentPathUri = dir.uri;
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(),
            TextField(
              controller: _fileNameController,
              decoration: const InputDecoration(labelText: 'File Name'),
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

  Widget _buildPathNavigator() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_upward),
          onPressed:
              _currentPathUri ==
                      ref
                          .read(appNotifierProvider)
                          .value!
                          .currentProject!
                          .rootUri
                  ? null
                  : () {
                    setState(() {
                      final segments = _currentPathUri.split('%2F');
                      _currentPathUri = segments
                          .sublist(0, segments.length - 1)
                          .join('%2F');
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
