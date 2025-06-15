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

// The private "hot" state for a single Markdown tab.
class _MarkdownTabState {
  final AppFlowyEditorState editorState;
  // Store the initial document state for dirty checking.
  final Document originalDocument;

  _MarkdownTabState({required this.editorState, required this.originalDocument});
}

class MarkdownEditorPlugin implements EditorPlugin {
  // The map that holds the "hot" state for all open markdown tabs.
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
  Future<EditorTab> createTab(DocumentFile file, String content) async {
    Document document;
    try {
      // AppFlowy Editor uses a JSON representation of the document.
      document = content.isEmpty
          ? Document()
          : Document.fromJson(json.decode(content));
    } catch (e) {
      // If content is not valid JSON (e.g., plain markdown text), create an empty document.
      // A more advanced implementation would parse Markdown to the AppFlowy format here.
      print("Error decoding markdown file, starting fresh: $e");
      document = Document();
    }
    
    final editorState = AppFlowyEditorState(document: document);
    
    _tabStates[file.uri] = _MarkdownTabState(
      editorState: editorState,
      originalDocument: document.copyWith(), // Deep copy for comparison
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
    // It's crucial to dispose the controller to prevent memory leaks.
    state?.editorState.dispose();
  }
  
  // This listener is called from the widget to notify the plugin of a change.
  void onDocumentChanged(MarkdownTab tab, WidgetRef ref) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;
    
    final isDirty = !const DeepCollectionEquality().equals(state.editorState.document.toJson(), state.originalDocument.toJson());
    final notifier = ref.read(tabStateProvider.notifier);
    if (isDirty) {
      notifier.markDirty(tab.file.uri);
    } else {
      notifier.markClean(tab.file.uri);
    }
  }
  
  @override
  void activateTab(EditorTab tab, Ref ref) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;

    // Update the global undo/redo providers with the state of the now-active tab.
    void updateUndoRedoState() {
      ref.read(markdownCanUndoProvider.notifier).state = state.editorState.canUndo;
      ref.read(markdownCanRedoProvider.notifier).state = state.editorState.canRedo;
    }
    state.editorState.addListener(updateUndoRedoState);
    updateUndoRedoState(); // Initial update
  }
  
  @override
  void deactivateTab(EditorTab tab, Ref ref) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;

    // Remove the listener to prevent this inactive tab from updating the global providers.
    state.editorState.removeListener(() {
        ref.read(markdownCanUndoProvider.notifier).state = state.editorState.canUndo;
        ref.read(markdownCanRedoProvider.notifier).state = state.editorState.canRedo;
    });
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

        // Update the original document to the new saved state
        final newOriginal = state.editorState.document.copyWith();
        _tabStates[tab.file.uri] = _MarkdownTabState(
          editorState: state.editorState,
          originalDocument: newOriginal,
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
        _tabStates[tab?.file.uri]?.editorState.undo();
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
        _tabStates[tab?.file.uri]?.editorState.redo();
      },
      canExecute: (ref) => ref.watch(markdownCanRedoProvider),
    ),
  ];
  
  @override
  Widget buildToolbar(WidgetRef ref) => const BottomToolbar();

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];
}