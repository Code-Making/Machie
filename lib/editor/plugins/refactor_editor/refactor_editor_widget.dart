// lib/editor/plugins/refactor_editor/refactor_editor_widget.dart

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glob/glob.dart';

import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../editor/editor_tab_models.dart';
import '../../../project/project_models.dart';
import '../../../project/services/project_hierarchy_service.dart';
import '../../../settings/settings_notifier.dart';
import 'refactor_editor_controller.dart';
import 'refactor_editor_hot_state.dart';
import 'refactor_editor_models.dart';
import 'occurrence_list_item.dart';
import '../../../logs/logs_provider.dart';
import '../../../utils/toast.dart';
import '../../../app/app_notifier.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/editor/services/text_editing_capability.dart';

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

class RefactorEditorWidgetState extends EditorWidgetState<RefactorEditorWidget> {
  late final RefactorController _controller;
  late final TextEditingController _findController;
  late final TextEditingController _replaceController;

  @override
  void init() {
    _controller = RefactorController(initialState: widget.tab.initialState);
    _findController = TextEditingController(text: _controller.searchTerm);
    _replaceController = TextEditingController(text: _controller.replaceTerm);
    _findController.addListener(() => _controller.updateSearchTerm(_findController.text));
    _replaceController.addListener(() => _controller.updateReplaceTerm(_replaceController.text));
  }
  
  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void onFirstFrameReady() {
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

    /// Compiles a set of string patterns into a list of structured Globs.
  List<_CompiledGlob> _compileGlobs(Set<String> patterns) {
    return patterns.map((p) {
      final isDirOnly = p.endsWith('/');
      final cleanPattern = isDirOnly ? p.substring(0, p.length - 1) : p;
      return (glob: Glob(cleanPattern), isDirectoryOnly: isDirOnly);
    }).toList();
  }

  Future<void> _handleFindOccurrences() async {
    _controller.startSearch();

    try {
      final repo = ref.read(projectRepositoryProvider);
      final settings = ref.read(settingsProvider).pluginSettings[RefactorSettings] as RefactorSettings?;
      final project = ref.read(appNotifierProvider).value?.currentProject;

      if (repo == null || settings == null || project == null) {
        throw Exception('Project, settings, or repository not available');
      }

      final results = <RefactorOccurrence>[];
      final globalIgnoreGlobs = _compileGlobs(settings.ignoredGlobPatterns);

      await _traverseAndSearch(
        directoryUri: project.rootUri,
        parentIgnoreGlobs: [],
        globalIgnoreGlobs: globalIgnoreGlobs,
        settings: settings,
        repo: repo,
        projectRootUri: project.rootUri,
        results: results,
      );
      
      _controller.completeSearch(results);
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, '[Refactor] Search failed');
      _controller.failSearch();
    }
  }

  Future<void> _traverseAndSearch({
    required String directoryUri,
    required List<_CompiledGlob> parentIgnoreGlobs,
    required List<_CompiledGlob> globalIgnoreGlobs,
    required RefactorSettings settings,
    required ProjectRepository repo,
    required String projectRootUri,
    required List<RefactorOccurrence> results,
  }) async {
    final hierarchyNotifier = ref.read(projectHierarchyServiceProvider.notifier);
    var directoryState = ref.read(projectHierarchyServiceProvider)[directoryUri];

    if (directoryState == null || directoryState is! AsyncData) {
        await hierarchyNotifier.loadDirectory(directoryUri);
        directoryState = ref.read(projectHierarchyServiceProvider)[directoryUri];
    }
    
    final entries = directoryState?.valueOrNull?.map((node) => node.file).toList() ?? [];

    List<_CompiledGlob> currentIgnoreGlobs = [];
    final gitignoreFile = entries.firstWhereOrNull((f) => f.name == '.gitignore');
    if (gitignoreFile != null && settings.useProjectGitignore) {
        try {
            final content = await repo.readFile(gitignoreFile.uri);
            final patterns = content.split('\n')
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty && !line.startsWith('#'))
                .toSet();
            currentIgnoreGlobs = _compileGlobs(patterns);
        } catch (_) { /* ignore unreadable file */ }
    }
    
    final activeIgnoreGlobs = [...parentIgnoreGlobs, ...currentIgnoreGlobs];

    for (final entry in entries) {
      final relativePath = repo.fileHandler.getPathForDisplay(entry.uri, relativeTo: projectRootUri)
          .replaceAll(r'\', '/');
      final pathFromCurrentDir = repo.fileHandler.getPathForDisplay(entry.uri, relativeTo: directoryUri)
          .replaceAll(r'\', '/');

      bool isIgnored = false;
      for (final compiledGlob in globalIgnoreGlobs) {
        if (compiledGlob.isDirectoryOnly && !entry.isDirectory) continue;
        if (compiledGlob.glob.matches(relativePath)) {
          isIgnored = true;
          break;
        }
      }
      if (isIgnored) continue;
      for (final compiledGlob in activeIgnoreGlobs) {
        if (compiledGlob.isDirectoryOnly && !entry.isDirectory) continue;
        if (compiledGlob.glob.matches(pathFromCurrentDir)) {
          isIgnored = true;
          break;
        }
      }
      if (isIgnored) continue;
      
      if (entry.isDirectory) {
        await _traverseAndSearch(
          directoryUri: entry.uri,
          parentIgnoreGlobs: activeIgnoreGlobs,
          globalIgnoreGlobs: globalIgnoreGlobs,
          settings: settings,
          repo: repo,
          projectRootUri: projectRootUri,
          results: results,
        );
      } else {
        if (settings.supportedExtensions.any((ext) => relativePath.endsWith(ext))) {
          final content = await repo.readFile(entry.uri);
          // Calculate hash here
          final fileContentHash = md5.convert(utf8.encode(content)).toString();
          final occurrencesInFile = _controller.searchInContent(
            content: content,
            fileUri: entry.uri,
            displayPath: relativePath,
            fileContentHash: fileContentHash, // Pass the hash
          );
          results.addAll(occurrencesInFile);
        }
      }
    }
  }

  Future<void> _handleApplyChanges() async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) {
      MachineToast.error("Project repository not available.");
      return;
    }

    final selected = _controller.selectedItems.toList();
    if (selected.isEmpty) return;

    final List<RefactorResultItem> processedItems = [];
    final Map<RefactorResultItem, String> failedItems = {};

    // Group by file URI to process one file at a time.
    final groupedByFile = selected.groupListsBy((item) => item.occurrence.fileUri);

    for (final entry in groupedByFile.entries) {
      final fileUri = entry.key;
      final itemsInFile = entry.value;
      final originalHash = itemsInFile.first.occurrence.fileContentHash;

      try {
        final currentContent = await repo.readFile(fileUri);
        final currentHash = md5.convert(utf8.encode(currentContent)).toString();

        // THE HASH CHECK
        if (currentHash != originalHash) {
          const reason = "File was modified externally.";
          for (final item in itemsInFile) {
            failedItems[item] = reason;
          }
          continue; // Skip to the next file
        }

        final lines = currentContent.split('\n');
        itemsInFile.sort((a, b) {
          final lineCmp = b.occurrence.lineNumber.compareTo(a.occurrence.lineNumber);
          if (lineCmp != 0) return lineCmp;
          return b.occurrence.startColumn.compareTo(a.occurrence.startColumn);
        });

        for (final item in itemsInFile) {
          final occ = item.occurrence;
          final line = lines[occ.lineNumber];
          lines[occ.lineNumber] = line.replaceRange(
            occ.startColumn,
            occ.startColumn + occ.matchedText.length,
            _controller.replaceTerm,
          );
        }

        final newContent = lines.join('\n');
        final fileMeta = await repo.getFileMetadata(fileUri);
        if (fileMeta == null) throw Exception("File metadata not found");
        await repo.writeFile(fileMeta, newContent);
        
        processedItems.addAll(itemsInFile);

      } catch (e, st) {
        ref.read(talkerProvider).handle(e, st, "Failed to apply refactor to $fileUri");
        final reason = e.toString();
        for (final item in itemsInFile) {
            failedItems[item] = reason;
        }
      }
    }
    
    // Update the UI state via the controller.
    _controller.updateItemsStatus(processed: processedItems, failed: failedItems);

    final message = "Replaced ${processedItems.length} occurrences." + (failedItems.isNotEmpty ? " ${failedItems.length} failed." : "");
    failedItems.isNotEmpty ? MachineToast.error(message) : MachineToast.info(message);
  }
  
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final allSelected = _controller.resultItems.isNotEmpty && 
                            _controller.selectedItems.length == _controller.resultItems.where((i) => i.status == ResultStatus.pending).length;
        return Column(
          children: [
            _buildInputPanel(),
            if (_controller.searchStatus == SearchStatus.searching) const LinearProgressIndicator(),
            Expanded(child: _buildResultsPanel(allSelected)),
            _buildActionPanel(),
          ],
        );
      },
    );
  }

  Widget _buildInputPanel() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findController,
                  decoration: const InputDecoration(labelText: 'Find', border: OutlineInputBorder()),
                  onSubmitted: (_) => _handleFindOccurrences(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _controller.searchStatus == SearchStatus.searching ? null : _handleFindOccurrences,
                child: const Text('Find All'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _replaceController,
            decoration: const InputDecoration(labelText: 'Replace', border: OutlineInputBorder()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _OptionCheckbox(
                label: 'Use Regex',
                value: _controller.isRegex,
                onChanged: (val) => _controller.toggleIsRegex(val ?? false),
              ),
              _OptionCheckbox(
                label: 'Case Sensitive',
                value: _controller.isCaseSensitive,
                onChanged: (val) => _controller.toggleCaseSensitive(val ?? false),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildResultsPanel(bool allSelected) {
    if (_controller.searchStatus == SearchStatus.idle) {
      return const Center(child: Text('Enter a search term and click "Find All"'));
    }
    if (_controller.searchStatus == SearchStatus.error) {
      return const Center(child: Text('An error occurred during search.', style: TextStyle(color: Colors.red)));
    }
    if (_controller.searchStatus == SearchStatus.complete && _controller.resultItems.isEmpty) {
      return Center(child: Text('No results found for "${_controller.searchTerm}"'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Text('${_controller.resultItems.length} results found.'),
              const Spacer(),
              const Text('Select All'),
              Checkbox(
                value: allSelected,
                tristate: !allSelected && _controller.selectedItems.isNotEmpty,
                onChanged: (val) => _controller.toggleSelectAll(val ?? false),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _controller.resultItems.length,
            itemBuilder: (context, index) {
              final resultItem = _controller.resultItems[index];
              final isSelected = _controller.selectedItems.contains(resultItem);
              
              return OccurrenceListItem(
                item: resultItem,
                isSelected: isSelected,
                onSelected: (_) => _controller.toggleItemSelection(resultItem),
                onJumpTo: () async {
                  final occurrence = resultItem.occurrence;
                  final edit = RevealRangeEdit(
                    range: TextRange(
                      start: TextPosition(line: occurrence.lineNumber, column: occurrence.startColumn),
                      end: TextPosition(line: occurrence.lineNumber, column: occurrence.startColumn + occurrence.matchedText.length),
                    ),
                  );
                  await ref.read(editorServiceProvider).openAndApplyEdit(occurrence.displayPath, edit);
                },
              );
            },
          ),
        ),
      ],
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
  final ValueChanged<bool?> onChanged;
  const _OptionCheckbox({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Checkbox(value: value, onChanged: onChanged), Text(label)]);
  }
}