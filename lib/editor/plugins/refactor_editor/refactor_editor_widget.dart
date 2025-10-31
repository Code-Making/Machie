// =========================================
// FINAL REFACTORED: lib/editor/plugins/refactor_editor/refactor_editor_widget.dart
// =========================================

import 'dart:async';
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
import '../../../app/app_notifier.dart';

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
  
  // ... dispose and onFirstFrameReady are unchanged

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

  /// Recursively finds all .gitignore files and builds a single Set of rooted Globs.
  Future<void> _loadGitignoreGlobsRecursive({
    required String directoryUri,
    required String relativePath,
    required ProjectRepository repo,
    required Set<Glob> collectedGlobs,
  }) async {
    final entries = await repo.listDirectory(directoryUri, includeHidden: true);
    final gitignoreFile = entries.firstWhere((f) => f.name == '.gitignore', orElse: () => VirtualDocumentFile(uri: '', name: ''));

    if (gitignoreFile.uri.isNotEmpty) {
      try {
        final content = await repo.readFile(gitignoreFile.uri);
        content.split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#'))
            .forEach((pattern) {
              // Root the pattern to the current directory path
              final rootedPattern = (relativePath.isEmpty) ? pattern : '$relativePath/$pattern';
              collectedGlobs.add(Glob(rootedPattern));
            });
      } catch (_) {}
    }

    for (final entry in entries) {
      if (entry.isDirectory) {
        final newRelativePath = (relativePath.isEmpty) ? entry.name : '$relativePath/${entry.name}';
        await _loadGitignoreGlobsRecursive(
          directoryUri: entry.uri,
          relativePath: newRelativePath,
          repo: repo,
          collectedGlobs: collectedGlobs,
        );
      }
    }
  }

  /// The main orchestration method.
  Future<void> _handleFindOccurrences() async {
    _controller.startSearch();

    try {
      final repo = ref.read(projectRepositoryProvider);
      final settings = ref.read(settingsProvider).pluginSettings[RefactorSettings] as RefactorSettings?;
      final project = ref.read(appNotifierProvider).value?.currentProject;

      if (repo == null || settings == null || project == null) {
        throw Exception('Project, settings, or repository not available');
      }

      // --- COMPILE ALL IGNORE PATTERNS ---
      final Set<Glob> allIgnoreGlobs = settings.ignoredGlobPatterns.map((p) => Glob(p)).toSet();

      if (settings.useProjectGitignore) {
        await _loadGitignoreGlobsRecursive(
          directoryUri: project.rootUri,
          relativePath: '',
          repo: repo,
          collectedGlobs: allIgnoreGlobs,
        );
      }
      // --- END COMPILE ---

      final results = <RefactorOccurrence>[];
      await _traverseAndSearch(
        directoryUri: project.rootUri,
        allIgnoreGlobs: allIgnoreGlobs.toList(), // Pass as a list for efficiency
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

  /// The recursive traversal logic, now much simpler.
  Future<void> _traverseAndSearch({
    required String directoryUri,
    required List<Glob> allIgnoreGlobs, // The single master list of rooted globs
    required RefactorSettings settings,
    required ProjectRepository repo,
    required String projectRootUri,
    required List<RefactorOccurrence> results,
  }) async {
    var directoryState = ref.read(directoryContentsProvider(directoryUri));
    if (directoryState == null || directoryState is! AsyncData) {
      await ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(directoryUri);
      directoryState = ref.read(projectHierarchyServiceProvider)[directoryUri];
    }
    
    final entries = directoryState?.valueOrNull?.map((node) => node.file).toList() ?? [];

    for (final entry in entries) {
      final relativePath = repo.fileHandler.getPathForDisplay(entry.uri, relativeTo: projectRootUri);

      // --- SIMPLIFIED AND CORRECT IGNORE LOGIC ---
      if (allIgnoreGlobs.any((glob) => glob.matches(relativePath))) {
        continue; // Prune this file or directory
      }
      
      if (entry.isDirectory) {
        await _traverseAndSearch(
          directoryUri: entry.uri,
          allIgnoreGlobs: allIgnoreGlobs,
          settings: settings,
          repo: repo,
          projectRootUri: projectRootUri,
          results: results,
        );
      } else {
        if (settings.supportedExtensions.any((ext) => relativePath.endsWith(ext))) {
          final content = await repo.readFile(entry.uri);
          final occurrencesInFile = _controller.searchInContent(
            content: content,
            fileUri: entry.uri,
            displayPath: relativePath,
          );
          results.addAll(occurrencesInFile);
        }
      }
    }
  }
  
  // ... (build methods and other overrides are completely unchanged)
  // They just read from the controller, so they don't need to be modified.
  
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final allSelected = _controller.occurrences.isNotEmpty && _controller.selectedOccurrences.length == _controller.occurrences.length;
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
    if (_controller.searchStatus == SearchStatus.complete && _controller.occurrences.isEmpty) {
      return Center(child: Text('No results found for "${_controller.searchTerm}"'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Text('${_controller.occurrences.length} results found.'),
              const Spacer(),
              const Text('Select All'),
              Checkbox(
                value: allSelected,
                tristate: !allSelected && _controller.selectedOccurrences.isNotEmpty,
                onChanged: (val) => _controller.toggleSelectAll(val ?? false),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _controller.occurrences.length,
            itemBuilder: (context, index) {
              final occurrence = _controller.occurrences[index];
              final isSelected = _controller.selectedOccurrences.contains(occurrence);
              return OccurrenceListItem(
                occurrence: occurrence,
                isSelected: isSelected,
                onSelected: (_) => _controller.toggleOccurrenceSelection(occurrence),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionPanel() {
    final canApply = _controller.selectedOccurrences.isNotEmpty;
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
            onPressed: canApply ? _controller.applyChanges : null,
            child: Text('Replace ${_controller.selectedOccurrences.length} selected'),
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