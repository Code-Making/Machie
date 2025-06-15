// lib/plugins/markdown_editor/markdown_editor_plugin.dart
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../command/command_models.dart';
import '../../command/command_widgets.dart';
import '../../data/file_handler/file_handler.dart';
import '../../session/session_models.dart';
import '../../session/tab_state.dart';
import '../plugin_models.dart';
import 'markdown_editor_models.dart';
import 'markdown_editor_state.dart';
import 'markdown_editor_widget.dart';

// CORRECTED: Use the correct `EditorState` class.
class _MarkdownTabState {
  final EditorState editorState;
  final Document originalDocument;

  _MarkdownTabState({required this.editorState, required this.originalDocument});
}

class MarkdownEditorPlugin implements EditorPlugin {
  final Map<String, _MarkdownTabState> _tabStates = {};

  @override
  String get name => 'Markdown Editor';
  @override
  Widget get icon => const Icon(Icons.edit_document);
  @override
  PluginSettings? get settings => null;
  @override
  Widget buildSettingsUI(PluginSettings settings) => const SizedBox.shrink();

  @override
  bool supportsFile(DocumentFile file) => file.name.endsWith('.md');

  @override
  Future<void> dispose() async {
    for (final state in _tabStates.values) {
      // CORRECTED: EditorState itself is the disposable object.
      state.editorState.dispose();
    }
    _tabStates.clear();
  }

  @override
  Future<EditorTab> createTab(DocumentFile file, String content) async {
    Document document;
    try {
      document = content.isEmpty
          // CORRECTED: Use the correct constructor for a blank document.
          ? EditorState.blank(withInitialText: false).document
          : Document.fromJson(json.decode(content));
    } catch (e) {
      document = markdownToDocument(content);
    }
    
    final editorState = EditorState(document: document);
    
    // CORRECTED: Deep copy must be done via JSON serialization.
    final originalJson = document.toJson();
    
    _tabStates[file.uri] = _MarkdownTabState(
      editorState: editorState,
      originalDocument: Document.fromJson(originalJson),
    );
    
    return MarkdownTab(file: file, plugin: this);
  }

  @override
  Future<EditorTab> createTabFromSerialization(Map<String, dynamic> tabJson, FileHandler fileHandler) async {
    final fileUri = tabJson['fileUri'] as String;
    final file = await fileHandler.getFileMetadata(fileUri);
    if (file == null) throw Exception('File not found for tab: $fileUri');
    final content = await fileHandler.readFile(fileUri);
    return createTab(file, content);
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final state = _tabStates[tab.file.uri];
    if (state == null) {
      return const Center(child: Text("Error: Markdown editor state not found."));
    }
    return MarkdownEditorWidget(
      key: ValueKey(tab.file.uri),
      tab: tab as MarkdownTab,
      plugin: this,
      editorState: state.editorState,
    );
  }

  @override
  void disposeTab(EditorTab tab) {
    final state = _tabStates.remove(tab.file.uri);
    // CORRECTED: EditorState is the object to dispose.
    state?.editorState.dispose();
  }
  
  void onDocumentChanged(MarkdownTab tab, WidgetRef ref) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;
    
    final isDirty = !const DeepCollectionEquality().equals(
      state.editorState.document.toJson(), 
      state.originalDocument.toJson()
    );

    final notifier = ref.read(tabStateProvider.notifier);
    if (isDirty) {
      notifier.markDirty(tab.file.uri);
    } else {
      notifier.markClean(tab.file.uri);
    }
  }
  
  // CORRECTED: EditorState now uses a ValueNotifier for selection.
  // We need to listen to that to update undo/redo state.
  void _updateUndoRedo(Ref ref, EditorState editorState) {
    ref.read(markdownCanUndoProvider.notifier).state = editorState.undoManager.canUndo;
    ref.read(markdownCanRedoProvider.notifier).state = editorState.undoManager.canRedo;
  }

  @override
  void activateTab(EditorTab tab, Ref ref) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;

    final editorState = state.editorState;
    void listener() => _updateUndoRedo(ref, editorState);

    editorState.undoManager.addListener(listener);
    _updateUndoRedo(ref, editorState); // Initial update
  }
  
  @override
  void deactivateTab(EditorTab tab, Ref ref) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;
    
    final editorState = state.editorState;
    void listener() => _updateUndoRedo(ref, editorState);
    
    editorState.undoManager.removeListener(listener);
  }

  @override
  List<Command> getCommands() => [
    BaseCommand(
      id: 'save',
      label: 'Save',
      icon: const Icon(Icons.save),
      defaultPosition: CommandPosition.appBar,
      sourcePlugin: runtimeType.toString(),
      execute: (ref) async {
        final appNotifier = ref.read(appNotifierProvider.notifier);
        final tab = appNotifier.state.value?.currentProject?.session.currentTab as MarkdownTab?;
        if (tab == null) return;
        final state = _tabStates[tab.file.uri];
        if (state == null) return;

        final jsonContent = json.encode(state.editorState.document.toJson());
        await appNotifier.saveCurrentTab(content: jsonContent);

        final newOriginalJson = state.editorState.document.toJson();
        _tabStates[tab.file.uri] = _MarkdownTabState(
          editorState: state.editorState,
          originalDocument: Document.fromJson(newOriginalJson),
        );
      },
      canExecute: (ref) => ref.watch(tabStateProvider)[ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab?.file.uri] ?? false,
    ),
    BaseCommand(
      id: 'undo',
      label: 'Undo',
      icon: const Icon(Icons.undo),
      defaultPosition: CommandPosition.pluginToolbar,
      sourcePlugin: runtimeType.toString(),
      execute: (ref) {
        final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
        // CORRECTED: Use the undoManager for undo/redo
        _tabStates[tab?.file.uri]?.editorState.undoManager.undo();
      },
      canExecute: (ref) => ref.watch(markdownCanUndoProvider),
    ),
    BaseCommand(
      id: 'redo',
      label: 'Redo',
      icon: const Icon(Icons.redo),
      defaultPosition: CommandPosition.pluginToolbar,
      sourcePlugin: runtimeType.toString(),
      execute: (ref) {
        final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
        // CORRECTED: Use the undoManager for undo/redo
        _tabStates[tab?.file.uri]?.editorState.undoManager.redo();
      },
      canExecute: (ref) => ref.watch(markdownCanRedoProvider),
    ),
  ];
  
  @override
  Widget buildToolbar(WidgetRef ref) => const BottomToolbar();

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];
}