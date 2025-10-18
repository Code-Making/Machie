// FILE: lib/editor/plugins/llm_editor/llm_editor_dialogs.dart

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/project/services/project_hierarchy_service.dart';

// NEW IMPORTS for split files
import 'package:machine/editor/plugins/llm_editor/context_widgets.dart';
import 'package:machine/editor/plugins/code_editor/code_themes.dart';


class EditMessageDialog extends ConsumerStatefulWidget {
  final ChatMessage initialMessage;
  const EditMessageDialog({required this.initialMessage});

  @override
  ConsumerState<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends ConsumerState<EditMessageDialog> {
  late final TextEditingController _textController;
  late final List<ContextItem> _contextItems;
  bool _canSave = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialMessage.content);
    _contextItems = List<ContextItem>.from(widget.initialMessage.context ?? []);
    _textController.addListener(_validate);
    _validate();
  }

  @override
  void dispose() {
    _textController.removeListener(_validate);
    _textController.dispose();
    super.dispose();
  }
  
  void _validate() {
    final canSave = _textController.text.trim().isNotEmpty || _contextItems.isNotEmpty;
    if (canSave != _canSave) {
      setState(() {
        _canSave = canSave;
      });
    }
  }

  Future<void> _addContext() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null) return;

    final file = await showDialog<DocumentFile>(
      context: context,
      builder: (context) => FilePickerLiteDialog(projectRootUri: project.rootUri),
    );

    if (file != null) {
      final repo = ref.read(projectRepositoryProvider)!;
      final content = await repo.readFile(file.uri);
      final relativePath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: project.rootUri);
      setState(() {
        _contextItems.add(ContextItem(source: relativePath, content: content));
        _validate();
      });
    }
  }

  void _onSave() {
    final newMessage = ChatMessage(
      role: 'user',
      content: _textController.text.trim(),
      context: _contextItems,
    );
    Navigator.of(context).pop(newMessage);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Message'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(icon: const Icon(Icons.attachment), onPressed: _addContext, tooltip: 'Add File Context'),
                IconButton(icon: const Icon(Icons.clear_all), onPressed: () => setState(() { _contextItems.clear(); _validate(); }), tooltip: 'Clear Context'),
              ],
            ),
            if (_contextItems.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _contextItems.map((item) => ContextItemCard(
                        item: item,
                        onRemove: () => setState(() { _contextItems.remove(item); _validate(); }),
                      )).toList(),
                    ),
                  ),
                ),
              ),
            const Divider(),
            Expanded(
              child: TextField(
                controller: _textController,
                autofocus: true,
                expands: true,
                maxLines: null,
                minLines: null,
                decoration: const InputDecoration(
                  hintText: 'Type your message...',
                  border: InputBorder.none,
                ),
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
          onPressed: _canSave ? _onSave : null,
          child: const Text('Save & Rerun'),
        ),
      ],
    );
  }
}

class FilePickerLiteDialog extends ConsumerStatefulWidget {
  final String projectRootUri;
  const FilePickerLiteDialog({required this.projectRootUri});

  @override
  ConsumerState<FilePickerLiteDialog> createState() => _FilePickerLiteDialogState();
}

class _FilePickerLiteDialogState extends ConsumerState<FilePickerLiteDialog> {
  late String _currentPathUri;

  @override
  void initState() {
    super.initState();
    _currentPathUri = widget.projectRootUri;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(_currentPathUri);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final directoryState = ref.watch(directoryContentsProvider(_currentPathUri));
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;

    return AlertDialog(
      title: const Text('Select a File for Context'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            if (fileHandler != null)
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _currentPathUri == widget.projectRootUri ? null : () {
                      final newPath = fileHandler.getParentUri(_currentPathUri);
                      ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(newPath);
                      setState(() => _currentPathUri = newPath);
                    },
                  ),
                  Expanded(
                    child: Text(
                      fileHandler.getPathForDisplay(_currentPathUri, relativeTo: widget.projectRootUri).isEmpty ? '/' : fileHandler.getPathForDisplay(_currentPathUri, relativeTo: widget.projectRootUri), // FIXED: Changed widget.projectUri to widget.projectRootUri
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const Divider(),
            Expanded(
              child: directoryState == null
                  ? const Center(child: CircularProgressIndicator())
                  : directoryState.when(
                      data: (nodes) {
                        final sortedNodes = List.of(nodes)..sort((a,b) {
                          if (a.file.isDirectory != b.file.isDirectory) return a.file.isDirectory ? -1 : 1;
                          return a.file.name.toLowerCase().compareTo(b.file.name.toLowerCase());
                        });

                        final filteredNodes = sortedNodes.where((node) {
                          if (node.file.isDirectory) return true;
                          final extension = node.file.name.split('.').lastOrNull?.toLowerCase();
                          return extension != null && CodeThemes.languageExtToNameMap.containsKey(extension);
                        }).toList();

                        return ListView.builder(
                          itemCount: filteredNodes.length,
                          itemBuilder: (context, index) {
                            final node = filteredNodes[index];
                            return ListTile(
                              leading: Icon(node.file.isDirectory ? Icons.folder_outlined : Icons.article_outlined),
                              title: Text(node.file.name),
                              onTap: () {
                                if (node.file.isDirectory) {
                                  ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(node.file.uri);
                                  setState(() => _currentPathUri = node.file.uri);
                                } else {
                                  Navigator.of(context).pop(node.file);
                                }
                              },
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Center(child: Text('Error: $err')),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}