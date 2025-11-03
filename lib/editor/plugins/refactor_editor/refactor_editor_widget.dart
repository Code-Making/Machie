// lib/editor/plugins/refactor_editor/refactor_editor_widget.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_notifier.dart';
import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../explorer/services/explorer_service.dart'; // Import for the listener
import '../../../logs/logs_provider.dart';
import '../../../project/project_models.dart';
import '../../../project/services/project_hierarchy_service.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/toast.dart';
import '../../editor_tab_models.dart';
import '../../services/editor_service.dart';
import '../../services/text_editing_capability.dart';
import '../../tab_state_manager.dart';

import 'occurrence_list_item.dart';
import 'refactor_editor_controller.dart';
import 'refactor_editor_hot_state.dart';
import 'refactor_editor_models.dart';

typedef _CompiledGlob = ({Glob glob, bool isDirectoryOnly});

class RefactorEditorWidget extends EditorWidget {
  @override
  final RefactorEditorTab tab;

  const RefactorEditorWidget({
    required GlobalKey<RefactorEditorWidgetState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  RefactorEditorWidgetState createState() => RefactorEditorWidgetState();
}

class RefactorEditorWidgetState extends EditorWidgetState<RefactorEditorWidget>
    with FileOperationEventListener {
  late final RefactorController _controller;
  late final TextEditingController _findController;
  late final TextEditingController _replaceController;

  // FIX 2: A much more generic regex to find any string in single or double quotes.
  // Group 1 captures the quote type, Group 2 captures the content.
  static final _pathRegex = RegExp(r"""(['"])(.+?)\1""");

  @override
  void init() {
    _controller = RefactorController(initialState: widget.tab.initialState);
    _findController = TextEditingController(text: _controller.searchTerm);
    _replaceController = TextEditingController(text: _controller.replaceTerm);

    _controller.addListener(() {
      if (_findController.text != _controller.searchTerm)
        _findController.text = _controller.searchTerm;
      if (_replaceController.text != _controller.replaceTerm)
        _replaceController.text = _controller.replaceTerm;
    });

    _findController.addListener(
      () => _controller.updateSearchTerm(_findController.text),
    );
    _replaceController.addListener(
      () => _controller.updateReplaceTerm(_replaceController.text),
    );

    ref.read(explorerServiceProvider).addListener(this);
  }

  @override
  void dispose() {
    ref.read(explorerServiceProvider).removeListener(this);

    _findController.dispose();
    _replaceController.dispose();
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Future<void> onFileOperation(FileOperationEvent event) async {
    if (!mounted) {
      return;
    }

    if (event is FileRenameEvent) {
      await _promptForPathRefactor(event.oldFile, event.newFile);
    }
  }

  @override
  void onFirstFrameReady() {
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  Future<void> _promptForPathRefactor(
    ProjectDocumentFile oldFile,
    ProjectDocumentFile newFile,
  ) async {
    if (!mounted) return;

    final repo = ref.read(projectRepositoryProvider);
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (repo == null || project == null || !mounted) return;

    final oldPath = repo.fileHandler.getPathForDisplay(
      oldFile.uri,
      relativeTo: project.rootUri,
    );
    final newPath = repo.fileHandler.getPathForDisplay(
      newFile.uri,
      relativeTo: project.rootUri,
    );

    final result = await showDialog<({String find, String replace})>(
      context: context,
      builder: (_) => _PathRefactorDialog(oldPath: oldPath, newPath: newPath),
    );

    if (!mounted) return;

    if (result != null) {
      _controller.setMode(RefactorMode.path);
      _controller.updateSearchTerm(result.find);
      _controller.updateReplaceTerm(result.replace);
    }
  }

  List<_CompiledGlob> _compileGlobs(Set<String> patterns) {
    return patterns.map((p) {
      final isDirOnly = p.endsWith('/');
      final cleanPattern = isDirOnly ? p.substring(0, p.length - 1) : p;
      return (glob: Glob(cleanPattern), isDirectoryOnly: isDirOnly);
    }).toList();
  }

  // --- DISPATCHER METHODS ---

  Future<void> _handleFindOccurrences() async {
    _controller.startSearch();
    try {
      if (_controller.mode == RefactorMode.path) {
        await _findPathOccurrences();
      } else {
        await _findTextOccurrences();
      }
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, '[Refactor] Search failed');
      _controller.failSearch();
    }
  }

  Future<void> _handleApplyChanges() async {
    if (_controller.mode == RefactorMode.path) {
      await _applyPathChanges();
    } else {
      await _applyTextChanges();
    }
  }

  // --- TEXT REFACTOR LOGIC ---

  Future<void> _findTextOccurrences() async {
    final repo = ref.read(projectRepositoryProvider);
    final settings =
        ref.read(settingsProvider).pluginSettings[RefactorSettings]
            as RefactorSettings?;
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (repo == null || settings == null || project == null)
      throw Exception('Prerequisites not met');

    final results = <RefactorOccurrence>[];
    await _traverseAndSearch(
      directoryUri: project.rootUri,
      onFileContent: (content, file, displayPath) {
        final fileContentHash = md5.convert(utf8.encode(content)).toString();
        results.addAll(
          _controller.searchInContent(
            content: content,
            fileUri: file.uri,
            displayPath: displayPath,
            fileContentHash: fileContentHash,
          ),
        );
      },
    );
    _controller.completeSearch(results);
  }
  
  String _getReplacementForMatch(Match match) {
    if (!_controller.replaceTerm.contains('\$')) {
      return _controller.replaceTerm;
    }
    return _controller.replaceTerm.replaceAllMapped(RegExp(r'\$(\d+)'), (placeholder) {
      final groupIndex = int.tryParse(placeholder.group(1) ?? '');
      if (groupIndex != null && groupIndex > 0 && groupIndex <= match.groupCount) {
        return match.group(groupIndex) ?? '';
      }
      return placeholder.group(0)!; // Return the original placeholder if index is invalid
    });
  }

  Future<void> _applyTextChanges() async {
    final List<RefactorResultItem> processedItems = [];
    final Map<RefactorResultItem, String> failedItems = {};
    final selected = _controller.selectedItems.toList();
    if (selected.isEmpty) return;

    final groupedByFile = selected.groupListsBy((item) => item.occurrence.fileUri);

    await _processFileGroups(
      groupedByFile: groupedByFile,
      generateEdits: (itemsInFile) {
        final List<ReplaceRangeEdit> lineEdits = [];

        // Group the selected items for this file by their line number.
        final groupedByLine = itemsInFile.groupListsBy((item) => item.occurrence.lineNumber);

        for (final lineEntry in groupedByLine.entries) {
          final lineNumber = lineEntry.key;
          final itemsOnLine = lineEntry.value;
          final originalLine = itemsOnLine.first.occurrence.lineContent;
          
          String newLineContent;

          if (_controller.isRegex) {
            final regex = RegExp(_controller.searchTerm, caseSensitive: _controller.isCaseSensitive);
            // Get the start columns of all selected occurrences on this line for quick lookup.
            final selectedColumns = itemsOnLine.map((item) => item.occurrence.startColumn).toSet();

            // Use replaceAllMapped to process every match on the line.
            newLineContent = originalLine.replaceAllMapped(regex, (match) {
              // If this specific match was selected by the user, replace it.
              if (selectedColumns.contains(match.start)) {
                return _getReplacementForMatch(match);
              }
              // Otherwise, return the original matched text, leaving it unchanged.
              return match.group(0)!;
            });
          } else {
            // For simple text replacement, build the new line manually from right to left
            // to avoid messing up indices.
            newLineContent = originalLine;
            final sortedItems = itemsOnLine.sortedBy<num>((item) => item.occurrence.startColumn).reversed;
            for (final item in sortedItems) {
              final occ = item.occurrence;
              newLineContent = newLineContent.replaceRange(
                occ.startColumn,
                occ.startColumn + occ.matchedText.length,
                _controller.replaceTerm,
              );
            }
          }

          // Create a single edit to replace the entire line.
          lineEdits.add(ReplaceRangeEdit(
            range: TextRange(
              start: TextPosition(line: lineNumber, column: 0),
              end: TextPosition(line: lineNumber, column: originalLine.length),
            ),
            replacement: newLineContent,
          ));
        }
        return lineEdits;
      },
      onSuccess: (items) => processedItems.addAll(items),
      onFailure: (items, reason) => failedItems.addAll({for (var item in items) item: reason}),
    );
    
    _controller.updateItemsStatus(processed: processedItems, failed: failedItems);
    final message = "Replaced ${processedItems.length} occurrences." + (failedItems.isNotEmpty ? " ${failedItems.length} failed." : "");
    failedItems.isNotEmpty ? MachineToast.error(message) : MachineToast.info(message);
  }

  // --- PATH REFACTOR LOGIC ---

  Future<void> _findPathOccurrences() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null) throw Exception('Project not available');

    final results = <RefactorOccurrence>[];
    final String searchTermAbsolute = p.normalize(_controller.searchTerm);

    await _traverseAndSearch(
      directoryUri: project.rootUri,
      onFileContent: (content, file, displayPath) {
        final fileContentHash = md5.convert(utf8.encode(content)).toString();
        final containingDir = p.dirname(displayPath);

        for (final match in _pathRegex.allMatches(content)) {
          // FIX 2: Use the correct group index (2) for our new, simpler regex.
          final matchedPath = match.group(2);

          // FIX 2: Add more robust filtering for path-like strings.
          if (matchedPath == null ||
              matchedPath.isEmpty ||
              matchedPath.startsWith('dart:'))
            continue;
          if (Uri.tryParse(matchedPath)?.isAbsolute ?? false) continue;

          try {
            // The core logic: resolve the path relative to the file it was found in.
            final resolvedPath = p.normalize(
              p.join(containingDir, matchedPath),
            );

            if (resolvedPath == searchTermAbsolute) {
              final pathStartOffsetInContent =
                  match.start + match.group(0)!.indexOf(matchedPath);
              final lineInfo = _getLineAndColumn(
                content,
                pathStartOffsetInContent,
              );

              results.add(
                RefactorOccurrence(
                  fileUri: file.uri,
                  displayPath: displayPath,
                  lineNumber: lineInfo.line,
                  startColumn: lineInfo.column,
                  lineContent: content.split('\n')[lineInfo.line],
                  matchedText: matchedPath,
                  fileContentHash: fileContentHash,
                ),
              );
            }
          } catch (e) {
            /* Ignore path resolution errors for invalid paths */
          }
        }
      },
    );
    _controller.completeSearch(results);
  }

  Future<void> _applyPathChanges() async {
    final List<RefactorResultItem> processedItems = [];
    final Map<RefactorResultItem, String> failedItems = {};
    final selected = _controller.selectedItems.toList();
    if (selected.isEmpty) return;

    final groupedByFile = selected.groupListsBy(
      (item) => item.occurrence.fileUri,
    );

    await _processFileGroups(
      groupedByFile: groupedByFile,
      generateEdits: (itemsInFile) {
        return itemsInFile.map((item) {
          final containingDir = p.dirname(item.occurrence.displayPath);
          final newRelativePath = p
              .relative(_controller.replaceTerm, from: containingDir)
              .replaceAll(r'\', '/');
          final occ = item.occurrence;

          return ReplaceRangeEdit(
            range: TextRange(
              start: TextPosition(
                line: occ.lineNumber,
                column: occ.startColumn,
              ),
              end: TextPosition(
                line: occ.lineNumber,
                column: occ.startColumn + occ.matchedText.length,
              ),
            ),
            replacement: newRelativePath,
          );
        }).toList();
      },
      onSuccess: (items) => processedItems.addAll(items),
      onFailure:
          (items, reason) =>
              failedItems.addAll({for (var item in items) item: reason}),
    );

    _controller.updateItemsStatus(
      processed: processedItems,
      failed: failedItems,
    );
    final message =
        "Updated ${processedItems.length} paths." +
        (failedItems.isNotEmpty ? " ${failedItems.length} failed." : "");
    failedItems.isNotEmpty
        ? MachineToast.error(message)
        : MachineToast.info(message);
  }

  // --- GENERIC HELPERS ---

  Future<void> _traverseAndSearch({
    required String directoryUri,
    required Function(
      String content,
      ProjectDocumentFile file,
      String displayPath,
    )
    onFileContent,
  }) async {
    final repo = ref.read(projectRepositoryProvider)!;
    final projectRootUri =
        ref.read(appNotifierProvider).value!.currentProject!.rootUri;
    final settings =
        ref.read(settingsProvider).pluginSettings[RefactorSettings]
            as RefactorSettings;

    final hierarchyNotifier = ref.read(
      projectHierarchyServiceProvider.notifier,
    );
    var directoryState =
        ref.read(projectHierarchyServiceProvider)[directoryUri];
    if (directoryState == null || directoryState is! AsyncData) {
      await hierarchyNotifier.loadDirectory(directoryUri);
      directoryState = ref.read(projectHierarchyServiceProvider)[directoryUri];
    }
    final entries =
        directoryState?.valueOrNull?.map((node) => node.file).toList() ?? [];

    final globalIgnoreGlobs = _compileGlobs(settings.ignoredGlobPatterns);
    List<_CompiledGlob> currentIgnoreGlobs = [];
    final gitignoreFile = entries.firstWhereOrNull(
      (f) => f.name == '.gitignore',
    );
    if (gitignoreFile != null && settings.useProjectGitignore) {
      try {
        final content = await repo.readFile(gitignoreFile.uri);
        final patterns =
            content
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty && !l.startsWith('#'))
                .toSet();
        currentIgnoreGlobs = _compileGlobs(patterns);
      } catch (_) {}
    }

    for (final entry in entries) {
      final relativePath = repo.fileHandler
          .getPathForDisplay(entry.uri, relativeTo: projectRootUri)
          .replaceAll(r'\', '/');
      bool isIgnored = globalIgnoreGlobs.any(
        (g) =>
            !(g.isDirectoryOnly && !entry.isDirectory) &&
            g.glob.matches(relativePath),
      );
      if (isIgnored) continue;

      final pathFromCurrentDir = repo.fileHandler
          .getPathForDisplay(entry.uri, relativeTo: directoryUri)
          .replaceAll(r'\', '/');
      isIgnored = currentIgnoreGlobs.any(
        (g) =>
            !(g.isDirectoryOnly && !entry.isDirectory) &&
            g.glob.matches(pathFromCurrentDir),
      );
      if (isIgnored) continue;

      if (entry.isDirectory) {
        await _traverseAndSearch(
          directoryUri: entry.uri,
          onFileContent: onFileContent,
        );
      } else {
        if (settings.supportedExtensions.any(
          (ext) => relativePath.endsWith(ext),
        )) {
          final content = await repo.readFile(entry.uri);
          onFileContent(content, entry, relativePath);
        }
      }
    }
  }

  ({int line, int column}) _getLineAndColumn(String content, int offset) {
    int line = 0;
    int lastLineStart = 0;
    for (int i = 0; i < offset; i++) {
      if (content[i] == '\n') {
        line++;
        lastLineStart = i + 1;
      }
    }
    return (line: line, column: offset - lastLineStart);
  }

  Future<void> _processFileGroups({
    required Map<String, List<RefactorResultItem>> groupedByFile,
    required List<ReplaceRangeEdit> Function(
      List<RefactorResultItem> itemsInFile,
    )
    generateEdits,
    required void Function(List<RefactorResultItem> items) onSuccess,
    required void Function(List<RefactorResultItem> items, String reason)
    onFailure,
  }) async {
    final repo = ref.read(projectRepositoryProvider)!;
    final editorService = ref.read(editorServiceProvider);
    final project = ref.read(appNotifierProvider).value!.currentProject!;
    final metadataMap = ref.read(tabMetadataProvider);
    final openTabsByUri = {
      for (var tab in project.session.tabs) metadataMap[tab.id]!.file.uri: tab,
    };

    for (final entry in groupedByFile.entries) {
      final fileUri = entry.key;
      final itemsInFile = entry.value;
      final originalHash = itemsInFile.first.occurrence.fileContentHash;
      final openTab = openTabsByUri[fileUri];

      if (openTab != null) {
        final editorState = await openTab.onReady.future;
        final metadata = metadataMap[openTab.id];
        if (editorState is! TextEditable) {
          onFailure(itemsInFile, "Editor not text-editable.");
          continue;
        }
        if (metadata?.isDirty ?? true) {
          onFailure(itemsInFile, "File has unsaved changes.");
          continue;
        }
        final editableState = editorState as TextEditable;
        final currentContent = await editableState.getTextContent();
        if (md5.convert(utf8.encode(currentContent)).toString() !=
            originalHash) {
          onFailure(itemsInFile, "File content changed.");
          continue;
        }

        final edits = generateEdits(itemsInFile);
        if (edits.length != itemsInFile.length) {
          onFailure(itemsInFile, "Could not generate all edits.");
          continue;
        }

        editableState.batchReplaceRanges(edits);
        editorService.markCurrentTabDirty();
        onSuccess(itemsInFile);
      } else {
        try {
          final currentContent = await repo.readFile(fileUri);
          if (md5.convert(utf8.encode(currentContent)).toString() !=
              originalHash) {
            onFailure(itemsInFile, "File modified externally.");
            continue;
          }

          final edits = generateEdits(itemsInFile);
          if (edits.length != itemsInFile.length) {
            onFailure(itemsInFile, "Could not generate all edits.");
            continue;
          }

          if (_controller.autoOpenFiles) {
            final success = await editorService.openAndApplyEdit(
              itemsInFile.first.occurrence.displayPath,
              BatchReplaceRangesEdit(edits: edits),
            );
            if (success) {
              onSuccess(itemsInFile);
            } else {
              onFailure(itemsInFile, "Failed to open and apply edits.");
            }
          } else {
            final lines = currentContent.split('\n');
            edits.sort((a, b) {
              final lineCmp = b.range.start.line.compareTo(a.range.start.line);
              if (lineCmp != 0) return lineCmp;
              return b.range.start.column.compareTo(a.range.start.column);
            });
            for (final edit in edits) {
              lines[edit.range.start.line] = lines[edit.range.start.line]
                  .replaceRange(
                    edit.range.start.column,
                    edit.range.end.column,
                    edit.replacement,
                  );
            }
            final fileMeta = await repo.getFileMetadata(fileUri);
            if (fileMeta == null) throw Exception("File not found");
            await repo.writeFile(fileMeta, lines.join('\n'));
            onSuccess(itemsInFile);
          }
        } catch (e) {
          onFailure(itemsInFile, e.toString());
        }
      }
    }
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    // Wrap the entire UI in a ListenableBuilder that listens to the controller.
    // This ensures that any part of the UI, including the action panel,
    // rebuilds when the controller's state changes.
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildInputPanel()),
                  if (_controller.searchStatus == SearchStatus.searching)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  _buildResultsSliver(), // No longer needs `allSelected` passed in.
                ],
              ),
            ),
            _buildActionPanel(), // This will now be rebuilt correctly.
          ],
        );
      },
    );
  }

  Widget _buildInputPanel() {
    final isPathMode = _controller.mode == RefactorMode.path;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findController,
                  decoration: const InputDecoration(
                    labelText: 'Find',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _handleFindOccurrences(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed:
                    _controller.searchStatus == SearchStatus.searching
                        ? null
                        : _handleFindOccurrences,
                child: const Text('Find All'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _replaceController,
            decoration: const InputDecoration(
              labelText: 'Replace',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),

          // FIX 1: Add the mode switcher UI
          SegmentedButton<RefactorMode>(
            segments: const [
              ButtonSegment(
                value: RefactorMode.text,
                icon: Icon(Icons.text_fields),
                label: Text('Text'),
              ),
              ButtonSegment(
                value: RefactorMode.path,
                icon: Icon(Icons.drive_file_move_rtl_outlined),
                label: Text('Path'),
              ),
            ],
            selected: {_controller.mode},
            onSelectionChanged: (newSelection) {
              _controller.setMode(newSelection.first);
            },
          ),
          const SizedBox(height: 4),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _OptionCheckbox(
                label: 'Use Regex',
                value: isPathMode ? false : _controller.isRegex,
                // Disable checkbox in path mode
                onChanged:
                    isPathMode
                        ? null
                        : (val) => _controller.toggleIsRegex(val ?? false),
              ),
              _OptionCheckbox(
                label: 'Case Sensitive',
                value: isPathMode ? true : _controller.isCaseSensitive,
                // Disable checkbox in path mode (paths are effectively case-sensitive)
                onChanged:
                    isPathMode
                        ? null
                        : (val) =>
                            _controller.toggleCaseSensitive(val ?? false),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _OptionCheckbox(
                label: 'Auto-open files',
                value: _controller.autoOpenFiles,
                onChanged:
                    (val) => _controller.toggleAutoOpenFiles(val ?? false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSliver() {
    if (_controller.searchStatus == SearchStatus.idle) {
      return SliverFillRemaining(child: Center(child: Text(_controller.mode == RefactorMode.path ? 'Enter a project-relative path to find all its references.' : 'Enter a search term and click "Find All"')));
    }
    if (_controller.searchStatus == SearchStatus.error) {
      return const SliverFillRemaining(child: Center(child: Text('An error occurred during search.', style: TextStyle(color: Colors.red))));
    }
    if (_controller.searchStatus == SearchStatus.complete && _controller.resultItems.isEmpty) {
      return SliverFillRemaining(child: Center(child: Text('No results found for "${_controller.searchTerm}"')));
    }

    final groupedItems = _controller.resultItems.groupListsBy((item) => item.occurrence.fileUri);
    
    // This logic is now inside the builder, so it always has the latest state.
    final pendingItems = _controller.resultItems.where((i) => i.status == ResultStatus.pending);
    final allSelected = pendingItems.isNotEmpty && _controller.selectedItems.length == pendingItems.length;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 12.0),
                child: Row(
                  children: [
                    Text('${_controller.resultItems.length} results found in ${groupedItems.length} files.'),
                    const Spacer(),
                    const Text('Select All'),
                    Checkbox(
                      value: allSelected,
                      tristate: !allSelected && _controller.selectedItems.isNotEmpty,
                      onChanged: (val) => _controller.toggleSelectAll(val ?? false),
                    ),
                  ],
                ),
              );
            }
            
            final groupIndex = index - 1;
            final fileUri = groupedItems.keys.elementAt(groupIndex);
            final itemsInFile = groupedItems[fileUri]!;

            return _FileResultCard(
              key: ValueKey(fileUri),
              itemsInFile: itemsInFile,
              controller: _controller,
            );
          },
          childCount: groupedItems.length + 1,
        ),
      ),
    );
  }

  Widget _buildActionPanel() {
    final canApply = _controller.selectedItems.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).bottomAppBarTheme.color,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            onPressed: canApply ? _handleApplyChanges : null,
            child: Text('Replace ${_controller.selectedItems.length} selected'),
          ),
        ],
      ),
    );
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    return RefactorEditorHotStateDto(
      searchTerm: _controller.searchTerm,
      replaceTerm: _controller.replaceTerm,
      isRegex: _controller.isRegex,
      isCaseSensitive: _controller.isCaseSensitive,
      autoOpenFiles: _controller.autoOpenFiles,
      mode: _controller.mode,
    );
  }

  @override
  Future<EditorContent> getContent() async => EditorContentString('{}');
  @override
  void redo() {}
  @override
  void syncCommandContext() {}
  @override
  void undo() {}
  @override
  void onSaveSuccess(String newHash) {}
}

class _OptionCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool?>? onChanged;
  const _OptionCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Checkbox(value: value, onChanged: onChanged), Text(label)],
    );
  }
}

class _PathRefactorDialog extends StatelessWidget {
  final String oldPath;
  final String newPath;

  const _PathRefactorDialog({required this.oldPath, required this.newPath});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update Path References?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A file or folder was moved. Do you want to find and update all references to it?',
          ),
          const SizedBox(height: 16),
          Text('From:', style: Theme.of(context).textTheme.bodySmall),
          Text(oldPath, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Text('To:', style: Theme.of(context).textTheme.bodySmall),
          Text(newPath, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () =>
                  Navigator.of(context).pop((find: oldPath, replace: newPath)),
          child: const Text('Update References'),
        ),
      ],
    );
  }
}

class _FileResultCard extends ConsumerStatefulWidget {
  final List<RefactorResultItem> itemsInFile;
  final RefactorController controller;

  const _FileResultCard({
    super.key,
    required this.itemsInFile,
    required this.controller,
  });

  @override
  ConsumerState<_FileResultCard> createState() => _FileResultCardState();
}

class _FileResultCardState extends ConsumerState<_FileResultCard> {
  bool _isFolded = false;

  List<Widget> _buildPathSegments(String path, BuildContext context) {
    final theme = Theme.of(context);
    final List<Widget> pathWidgets = [];
    final segments = path.split('/');

    final baseStyle = theme.textTheme.titleSmall;
    final normalColor = baseStyle?.color?.withOpacity(0.9);
    final darkerColor =
        normalColor != null ? Color.lerp(normalColor, Colors.black, 0.1) : null;
    final separatorStyle = baseStyle?.copyWith(color: theme.dividerColor);

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final color = i % 2 == 0 ? normalColor : darkerColor;

      pathWidgets.add(
        Text(
          segment,
          style: baseStyle?.copyWith(color: color, fontWeight: FontWeight.bold),
        ),
      );

      if (i < segments.length - 1) {
        pathWidgets.add(Text(' / ', style: separatorStyle));
      }
    }
    return pathWidgets;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileUri = widget.itemsInFile.first.occurrence.fileUri;
    final displayPath = widget.itemsInFile.first.occurrence.displayPath;

    final pendingInFile =
        widget.itemsInFile
            .where((i) => i.status == ResultStatus.pending)
            .toList();
    final selectedInFileCount =
        widget.controller.selectedItems
            .where((i) => i.occurrence.fileUri == fileUri)
            .length;
    final isFileChecked =
        pendingInFile.isNotEmpty && selectedInFileCount == pendingInFile.length;
    final isFileTristate =
        selectedInFileCount > 0 && selectedInFileCount < pendingInFile.length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(
              left: 4.0,
              right: 8.0,
              top: 4.0,
              bottom: 4.0,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8.0),
                topRight: Radius.circular(8.0),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  value: isFileChecked,
                  tristate: isFileTristate,
                  onChanged:
                      (val) => widget.controller.toggleSelectAllForFile(
                        fileUri,
                        val ?? false,
                      ),
                ),
                Flexible(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: _buildPathSegments(displayPath, context),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${widget.itemsInFile.length})',
                  style: theme.textTheme.bodySmall,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _isFolded ? Icons.unfold_more : Icons.unfold_less,
                    size: 20,
                  ),
                  tooltip: _isFolded ? 'Unfold Results' : 'Fold Results',
                  onPressed: () => setState(() => _isFolded = !_isFolded),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child:
                _isFolded
                    ? const SizedBox(width: double.infinity)
                    : Column(
                      children:
                          widget.itemsInFile.map((item) {
                            return OccurrenceListItem(
                              item: item,
                              isSelected: widget.controller.selectedItems
                                  .contains(item),
                              onSelected:
                                  (_) => widget.controller.toggleItemSelection(
                                    item,
                                  ),
                              onJumpTo: () async {
                                final occurrence = item.occurrence;
                                final edit = RevealRangeEdit(
                                  range: TextRange(
                                    start: TextPosition(
                                      line: occurrence.lineNumber,
                                      column: occurrence.startColumn,
                                    ),
                                    end: TextPosition(
                                      line: occurrence.lineNumber,
                                      column:
                                          occurrence.startColumn +
                                          occurrence.matchedText.length,
                                    ),
                                  ),
                                );
                                await ref
                                    .read(editorServiceProvider)
                                    .openAndApplyEdit(
                                      occurrence.displayPath,
                                      edit,
                                    );
                              },
                            );
                          }).toList(),
                    ),
          ),
        ],
      ),
    );
  }
}
