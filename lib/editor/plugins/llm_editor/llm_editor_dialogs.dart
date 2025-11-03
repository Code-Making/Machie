// FILE: lib/editor/plugins/llm_editor/llm_editor_dialogs.dart

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../project/services/project_hierarchy_service.dart';
import '../code_editor/code_themes.dart';
import 'context_widgets.dart';
import 'llm_editor_models.dart';

// NEW: Provider to remember the last path within the current session.
final filePickerLastPathProvider = StateProvider<String?>((ref) => null);

class EditMessageDialog extends ConsumerStatefulWidget {
  final ChatMessage initialMessage;
  const EditMessageDialog({super.key, required this.initialMessage});

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
    _textController = TextEditingController(
      text: widget.initialMessage.content,
    );
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
    final canSave =
        _textController.text.trim().isNotEmpty || _contextItems.isNotEmpty;
    if (canSave != _canSave) {
      setState(() {
        _canSave = canSave;
      });
    }
  }

  // MODIFIED: This function now handles a list of files.
  Future<void> _addContext() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null) return;

    final files = await showDialog<List<DocumentFile>>(
      context: context,
      builder:
          (context) => FilePickerLiteDialog(projectRootUri: project.rootUri),
    );

    if (files != null && files.isNotEmpty) {
      final repo = ref.read(projectRepositoryProvider)!;
      for (final file in files) {
        // Avoid adding duplicates
        if (_contextItems.any((item) => item.source == file.name)) continue;

        final content = await repo.readFile(file.uri);
        final relativePath = repo.fileHandler.getPathForDisplay(
          file.uri,
          relativeTo: project.rootUri,
        );

        // No need for setState in loop, add all then setState once.
        _contextItems.add(ContextItem(source: relativePath, content: content));
      }
      setState(() {
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
    // ... rest of the EditMessageDialog build method is unchanged ...
    return AlertDialog(
      title: const Text('Edit Message'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attachment),
                  onPressed: _addContext,
                  tooltip: 'Add File Context',
                ),
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  onPressed:
                      () => setState(() {
                        _contextItems.clear();
                        _validate();
                      }),
                  tooltip: 'Clear Context',
                ),
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
                      children:
                          _contextItems
                              .map(
                                (item) => ContextItemCard(
                                  item: item,
                                  onRemove:
                                      () => setState(() {
                                        _contextItems.remove(item);
                                        _validate();
                                      }),
                                ),
                              )
                              .toList(),
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

// ENTIRELY REWRITTEN/REFACTORED WIDGET
class FilePickerLiteDialog extends ConsumerStatefulWidget {
  final String projectRootUri;
  const FilePickerLiteDialog({super.key, required this.projectRootUri});

  @override
  ConsumerState<FilePickerLiteDialog> createState() =>
      _FilePickerLiteDialogState();
}

class _FilePickerLiteDialogState extends ConsumerState<FilePickerLiteDialog> {
  late String _currentPathUri;
  bool _isMultiSelectMode = false;
  final Set<DocumentFile> _selectedFiles = {};

  @override
  void initState() {
    super.initState();
    // NEW: Use the provider to get the last path, or default to the root.
    _currentPathUri =
        ref.read(filePickerLastPathProvider) ?? widget.projectRootUri;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(projectHierarchyServiceProvider.notifier)
            .loadDirectory(_currentPathUri);
      }
    });
  }

  // NEW: Helper function to change directories and update the session provider
  void _setCurrentPath(String newPath) {
    ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(newPath);
    ref.read(filePickerLastPathProvider.notifier).state = newPath;
    setState(() => _currentPathUri = newPath);
  }

  void _toggleMultiSelectMode(DocumentFile? initialFile) {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      _selectedFiles.clear();
      if (_isMultiSelectMode && initialFile != null) {
        _selectedFiles.add(initialFile);
      }
    });
  }

  void _toggleFileSelection(DocumentFile file) {
    setState(() {
      if (_selectedFiles.contains(file)) {
        _selectedFiles.remove(file);
      } else {
        _selectedFiles.add(file);
      }
    });
  }

  Future<void> _onLongPressFolder(DocumentFile folder) async {
    final result = await showDialog<bool?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('Add all files from "${folder.name}"?'),
            content: const Text(
              'This will add all compatible text files to the context.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Folder only'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Folder & Subfolders'),
              ),
            ],
          ),
    );

    if (result != null) {
      final List<DocumentFile> filesToAdd = await _gatherFiles(folder, result);
      if (mounted) {
        Navigator.of(context).pop(filesToAdd);
      }
    }
  }

  Future<List<DocumentFile>> _gatherFiles(
    DocumentFile startFolder,
    bool recursive,
  ) async {
    final List<DocumentFile> gatheredFiles = [];
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return [];

    final queue = [startFolder];

    while (queue.isNotEmpty) {
      final currentFolder = queue.removeAt(0);
      try {
        final children = await repo.listDirectory(currentFolder.uri);
        for (final child in children) {
          if (child.isDirectory) {
            if (recursive) {
              queue.add(child);
            }
          } else {
            final extension = child.name.split('.').lastOrNull?.toLowerCase();
            if (extension != null &&
                CodeThemes.languageExtToNameMap.containsKey(extension)) {
              gatheredFiles.add(child);
            }
          }
        }
      } catch (e) {
        // Could be a permissions issue, just skip this directory
      }
    }
    return gatheredFiles;
  }

  @override
  Widget build(BuildContext context) {
    final directoryState = ref.watch(
      directoryContentsProvider(_currentPathUri),
    );
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;

    Widget titleWidget;
    if (_isMultiSelectMode) {
      titleWidget = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${_selectedFiles.length} Selected'),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _toggleMultiSelectMode(null),
          ),
        ],
      );
    } else {
      titleWidget = const Text('Select a File for Context');
    }

    return AlertDialog(
      title: titleWidget,
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
                    onPressed:
                        _currentPathUri == widget.projectRootUri
                            ? null
                            : () {
                              final newPath = fileHandler.getParentUri(
                                _currentPathUri,
                              );
                              _setCurrentPath(newPath); // MODIFIED
                            },
                  ),
                  Expanded(
                    child: Text(
                      fileHandler
                              .getPathForDisplay(
                                _currentPathUri,
                                relativeTo: widget.projectRootUri,
                              )
                              .isEmpty
                          ? '/'
                          : fileHandler.getPathForDisplay(
                            _currentPathUri,
                            relativeTo: widget.projectRootUri,
                          ),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const Divider(),
            Expanded(
              child:
                  directoryState == null
                      ? const Center(child: CircularProgressIndicator())
                      : directoryState.when(
                        data: (nodes) {
                          final sortedNodes = List.of(nodes)..sort((a, b) {
                            if (a.file.isDirectory != b.file.isDirectory) {
                              return a.file.isDirectory ? -1 : 1;
                            }
                            return a.file.name.toLowerCase().compareTo(
                              b.file.name.toLowerCase(),
                            );
                          });

                          final filteredNodes =
                              sortedNodes.where((node) {
                                if (node.file.isDirectory) return true;
                                final extension =
                                    node.file.name
                                        .split('.')
                                        .lastOrNull
                                        ?.toLowerCase();
                                return extension != null &&
                                    CodeThemes.languageExtToNameMap.containsKey(
                                      extension,
                                    );
                              }).toList();

                          return ListView.builder(
                            itemCount: filteredNodes.length,
                            itemBuilder: (context, index) {
                              final node = filteredNodes[index];
                              final isSelected = _selectedFiles.contains(
                                node.file,
                              );

                              if (node.file.isDirectory) {
                                return ListTile(
                                  leading: const Icon(Icons.folder_outlined),
                                  title: Text(node.file.name),
                                  onTap:
                                      () => _setCurrentPath(
                                        node.file.uri,
                                      ), // MODIFIED
                                  onLongPress:
                                      () =>
                                          _onLongPressFolder(node.file), // NEW
                                );
                              } else {
                                // It's a file
                                return ListTile(
                                  leading:
                                      _isMultiSelectMode
                                          ? Checkbox(
                                            value: isSelected,
                                            onChanged:
                                                (_) => _toggleFileSelection(
                                                  node.file,
                                                ),
                                          )
                                          : const Icon(Icons.article_outlined),
                                  title: Text(node.file.name),
                                  onTap: () {
                                    if (_isMultiSelectMode) {
                                      _toggleFileSelection(node.file);
                                    } else {
                                      Navigator.of(context).pop([node.file]);
                                    }
                                  },
                                  onLongPress: () {
                                    if (!_isMultiSelectMode) {
                                      _toggleMultiSelectMode(node.file);
                                    }
                                  },
                                );
                              }
                            },
                          );
                        },
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
      actions:
          _isMultiSelectMode
              ? [
                TextButton(
                  onPressed: () => _toggleMultiSelectMode(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed:
                      _selectedFiles.isNotEmpty
                          ? () =>
                              Navigator.of(context).pop(_selectedFiles.toList())
                          : null,
                  child: const Text('Add Selected'),
                ),
              ]
              : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
    );
  }
}
