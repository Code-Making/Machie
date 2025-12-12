import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/project/services/project_hierarchy_service.dart';

// Helper class for the result
class TexturePackerImportResult {
  final List<ProjectDocumentFile> files;
  final bool asSprites;

  TexturePackerImportResult(this.files, this.asSprites);
}

final _tpFilePickerLastPathProvider = StateProvider<String?>((ref) => null);

class TexturePackerFilePickerDialog extends ConsumerStatefulWidget {
  final String projectRootUri;
  const TexturePackerFilePickerDialog({super.key, required this.projectRootUri});

  @override
  ConsumerState<TexturePackerFilePickerDialog> createState() => _TexturePackerFilePickerDialogState();
}

class _TexturePackerFilePickerDialogState extends ConsumerState<TexturePackerFilePickerDialog> {
  late String _currentPathUri;
  final Set<ProjectDocumentFile> _selectedFiles = {};
  bool _importAsSprites = false; // The new option

  @override
  void initState() {
    super.initState();
    _currentPathUri = ref.read(_tpFilePickerLastPathProvider) ?? widget.projectRootUri;
    
    // Initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(_currentPathUri);
      }
    });
  }

  void _setCurrentPath(String newPath) {
    ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(newPath);
    ref.read(_tpFilePickerLastPathProvider.notifier).state = newPath;
    setState(() => _currentPathUri = newPath);
  }

  void _toggleFileSelection(ProjectDocumentFile file) {
    setState(() {
      if (_selectedFiles.contains(file)) {
        _selectedFiles.remove(file);
      } else {
        _selectedFiles.add(file);
      }
    });
  }

  // Allow selecting a whole folder of PNGs
  Future<void> _onLongPressFolder(ProjectDocumentFile folder) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select all images in "${folder.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Select All')),
        ],
      ),
    );

    if (result == true) {
      final files = await _gatherPngFiles(folder);
      setState(() {
        _selectedFiles.addAll(files);
      });
    }
  }

  Future<List<ProjectDocumentFile>> _gatherPngFiles(ProjectDocumentFile folder) async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return [];
    
    // Non-recursive for simplicity in this context, or recursive if desired.
    // Keeping it shallow (current folder) usually safer for UX unless specified.
    try {
      final children = await repo.listDirectory(folder.uri);
      return children.where((f) => !f.isDirectory && f.name.toLowerCase().endsWith('.png')).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final directoryState = ref.watch(directoryContentsProvider(_currentPathUri));
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_selectedFiles.isEmpty 
            ? 'Select Images' 
            : '${_selectedFiles.length} Selected'),
          if (_selectedFiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear Selection',
              onPressed: () => setState(() => _selectedFiles.clear()),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            // Navigation Bar
            if (fileHandler != null)
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _currentPathUri == widget.projectRootUri
                        ? null
                        : () {
                            final parent = fileHandler.getParentUri(_currentPathUri);
                            _setCurrentPath(parent);
                          },
                  ),
                  Expanded(
                    child: Text(
                      fileHandler.getPathForDisplay(_currentPathUri, relativeTo: widget.projectRootUri).isEmpty
                          ? '/'
                          : fileHandler.getPathForDisplay(_currentPathUri, relativeTo: widget.projectRootUri),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const Divider(),
            // File List
            Expanded(
              child: directoryState == null
                  ? const Center(child: CircularProgressIndicator())
                  : directoryState.when(
                      data: (nodes) {
                        final sorted = List.of(nodes)..sort((a, b) {
                          if (a.file.isDirectory != b.file.isDirectory) {
                            return a.file.isDirectory ? -1 : 1;
                          }
                          return a.file.name.toLowerCase().compareTo(b.file.name.toLowerCase());
                        });

                        final filtered = sorted.where((n) {
                          return n.file.isDirectory || n.file.name.toLowerCase().endsWith('.png');
                        }).toList();

                        return ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final node = filtered[index];
                            final isSelected = _selectedFiles.contains(node.file);

                            if (node.file.isDirectory) {
                              return ListTile(
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(node.file.name),
                                onTap: () => _setCurrentPath(node.file.uri),
                                onLongPress: () => _onLongPressFolder(node.file),
                              );
                            } else {
                              return ListTile(
                                leading: Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => _toggleFileSelection(node.file),
                                ),
                                title: Text(node.file.name),
                                onTap: () => _toggleFileSelection(node.file),
                              );
                            }
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, s) => Center(child: Text('Error: $e')),
                    ),
            ),
            const Divider(),
            // Option Checkbox
            CheckboxListTile(
              value: _importAsSprites,
              onChanged: (val) => setState(() => _importAsSprites = val ?? false),
              title: const Text('Import as Single Sprites / Frames'),
              subtitle: const Text('Automatically sets grid size to image size'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
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
          onPressed: _selectedFiles.isEmpty
              ? null
              : () {
                  final sortedFiles = _selectedFiles.toList()
                    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                  
                  Navigator.of(context).pop(TexturePackerImportResult(sortedFiles, _importAsSprites));
                },
          child: const Text('Import'),
        ),
      ],
    );
  }
}