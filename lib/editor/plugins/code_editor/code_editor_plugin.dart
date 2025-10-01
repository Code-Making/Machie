// =========================================
// FILE: lib/editor/plugins/code_editor/code_editor_plugin.dart
// =========================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:collection/collection.dart';

import 'code_themes.dart';
import 'code_editor_models.dart';
import 'code_editor_widgets.dart';
import 'code_editor_settings_widget.dart';
import 'code_editor_state.dart'; // <-- ADD THIS IMPORT
import 'code_editor_hot_state_adapter.dart'; // ADDED
import 'code_editor_hot_state_dto.dart'; // ADDED


import '../plugin_models.dart';
import '../../editor_tab_models.dart';
import '../../tab_state_manager.dart';
import '../../../app/app_commands.dart'; // Import for scratchpadTabId
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../command/command_widgets.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/dto/tab_hot_state_dto.dart'; // ADDED
import '../../../data/cache/type_adapters.dart'; // ADDED
import '../../../project/services/cache_service.dart';
import '../../../project/project_models.dart';


class CodeEditorPlugin implements EditorPlugin {
  static const String pluginId = 'com.machine.code_editor';
  static const String hotStateId = 'com.machine.code_editor_state';

  @override
  String get id => pluginId;
  @override
  String get name => 'Code Editor';
  @override
  Widget get icon => const Icon(Icons.code);
  @override
  final PluginSettings? settings = CodeEditorSettings();
  @override
  Widget buildSettingsUI(PluginSettings settings) =>
      CodeEditorSettingsUI(settings: settings as CodeEditorSettings);
  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  Type? get hotStateDtoRuntimeType => CodeEditorHotStateDto;

  @override
  Widget wrapCommandToolbar(Widget toolbar) {
    // This plugin needs to wrap toolbars to handle editor focus correctly.
    return CodeEditorTapRegion(child: toolbar);
  }
  
  @override
  Future<void> dispose() async {}
  @override
  void disposeTab(EditorTab tab) {}

  @override
  bool supportsFile(DocumentFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    return CodeThemes.languageExtToNameMap.containsKey(ext);
  }

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];

  @override
  String get hotStateDtoType => hotStateId;

  @override
  TypeAdapter<TabHotStateDto> get hotStateAdapter =>
      CodeEditorHotStateAdapter();

  /// Helper to get the active editor's state object.
  CodeEditorMachineState? _getEditorState(EditorTab tab) {
    if (tab.editorKey.currentState is CodeEditorMachineState) {
      return tab.editorKey.currentState as CodeEditorMachineState;
    }
    return null;
  }

  @override
  Future<TabHotStateDto?> serializeHotState(EditorTab tab) async {
    final editorState = _getEditorState(tab);
    if (editorState == null) return null;
    
    final stateMap = editorState.getHotState();
    // THE FIX: Construct the DTO with the language key.
    return CodeEditorHotStateDto(
      content: stateMap['content'],
      languageKey: stateMap['languageKey'],
    );
  }
  
  @override
  List<CommandPosition> getCommandPositions() => [];

  @override
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}

  @override
  Future<EditorTab> createTab(DocumentFile file, EditorInitData initData, {String? id}) async {
    String initialContent;
    String? initialLanguageKey;

    // Prioritize hot state if it exists
    if (initData.hotState is CodeEditorHotStateDto) {
      final hotState = initData.hotState as CodeEditorHotStateDto;
      initialContent = hotState.content;
      initialLanguageKey = hotState.languageKey;
    } else {
      // Fallback to initial data from the file
      initialContent = initData.stringData ?? '';
      initialLanguageKey = null;
    }

    return CodeEditorTab(
      plugin: this,
      initialContent: initialContent,
      initialLanguageKey: initialLanguageKey,
      id: id,
    );
  }

  @override
  Future<EditorTab> createTabFromSerialization(
    Map<String, dynamic> tabJson,
    FileHandler fileHandler,
  ) async {
    final fileUri = tabJson['fileUri'] as String;
    final file = await fileHandler.getFileMetadata(fileUri);
    if (file == null) {
      throw Exception('File not found for tab URI: $fileUri');
    }
    final content = await fileHandler.readFile(fileUri);
    final initData = EditorInitData(stringData: content);
    return createTab(file, initData);
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final codeTab = tab as CodeEditorTab;
    return CodeEditorMachine(key: codeTab.editorKey, tab: codeTab);
  }

  /// Helper to find the state of the currently active editor widget.
  CodeEditorMachineState? _getActiveEditorState(WidgetRef ref) {
    final tab = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab,
      ),
    );
    if (tab is! CodeEditorTab) return null;
    return tab.editorKey.currentState as CodeEditorMachineState?;
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    return CodeEditorTapRegion(child: const BottomToolbar());
  }

  @override
  List<Command> getAppCommands() => [
    BaseCommand(
      id: 'open_scratchpad',
      label: 'Open Scratchpad',
      icon: const Icon(Icons.edit_note),
      defaultPosition: AppCommandPositions.appBar,
      sourcePlugin: 'App',
      canExecute:
          (ref) => ref.watch(
            appNotifierProvider.select((s) => s.value?.currentProject != null),
          ),
      execute: (ref) async {
        final appNotifier = ref.read(appNotifierProvider.notifier);
        final project = ref.read(appNotifierProvider).value!.currentProject!;

        final existingTab = project.session.tabs.firstWhereOrNull(
          (t) => t.id == AppCommands.scratchpadTabId,
        );
        if (existingTab != null) {
          final index = project.session.tabs.indexOf(existingTab);
          appNotifier.switchTab(index);
          return;
        }

        final cacheService = ref.read(cacheServiceProvider);
        final codeEditorPlugin = this;
        final scratchpadFile = VirtualDocumentFile(
          uri: 'scratchpad://${project.id}',
          name: 'Scratchpad',
        );

        // Try to load cached DTO.
        final cachedDto = await cacheService.getTabState(
          project.id,
          AppCommands.scratchpadTabId,
        );

        // Create the unified init data object.
        final initData = EditorInitData(
          stringData: '', // No file to read, so default to empty string.
          hotState: cachedDto,
        );

        final newTab = await codeEditorPlugin.createTab(
          scratchpadFile,
          initData,
          id: AppCommands.scratchpadTabId,
        );

        final newTabs = [...project.session.tabs, newTab];
        final newProject = project.copyWith(
          session: project.session.copyWith(
            tabs: newTabs,
            currentTabIndex: newTabs.length - 1,
          ),
        );
        appNotifier.updateCurrentProject(newProject);

        final metadataNotifier = ref.read(tabMetadataProvider.notifier);
        metadataNotifier.initTab(newTab.id, scratchpadFile);
        metadataNotifier.markDirty(newTab.id);
      },
    ),
  ];

  // The command definitions are now correct. They find the active
  // editor's State object and call public methods on it. The canExecute
  // logic correctly watches the tabMetadataProvider for changes in dirty status.
  @override
  List<Command> getCommands() => [
    _createCommand(
      id: 'save',
      label: 'Save',
      icon: Icons.save,
      defaultPosition: AppCommandPositions.appBar,
      execute: (ref, editor) => editor?.save(),
      // REFACTORED: The 'isDirty' flag is now on the metadata.
      canExecute: (ref, editor) {
        if (editor == null) return false;
        // Watch the metadata for the current tab to react to dirty state changes.
        final metadata = ref.watch(
          tabMetadataProvider.select((m) => m[editor.widget.tab.id]),
        );
        return metadata?.isDirty ?? false;
      },
    ),
    _createCommand(
      id: 'goto_line',
      label: 'Go to Line',
      icon: Icons.numbers, // Or Icons.line_weight
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute:
          (ref, editor) =>
              editor?.showGoToLineDialog(), // Method we will create
    ),
    _createCommand(
      id: 'select_line',
      label: 'Select Line',
      icon:
          Icons.horizontal_rule, // A fitting icon for selecting a line segment
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute:
          (ref, editor) => editor?.selectCurrentLine(), // Method to be created
    ),
    _createCommand(
      id: 'select_chunk',
      label: 'Select Chunk/Block',
      icon: Icons.unfold_more, // A fitting icon for selecting a code block
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute:
          (ref, editor) => editor?.selectCurrentChunk(), // Method to be created
    ),
    _createCommand(
      id: 'extend_selection',
      label: 'Extend Selection',
      icon: Icons.code, // A different icon to distinguish from 'Select All'
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute:
          (ref, editor) => editor?.extendSelection(), // Method we will create
      canExecute: (ref, editor) => editor != null,
    ),
    _createCommand(
      id: 'find',
      label: 'Find',
      icon: Icons.search,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute:
          (ref, editor) => editor?.showFindPanel(), // Method we will create
      canExecute: (ref, editor) => editor != null,
    ),
    _createCommand(
      id: 'find_and_replace',
      label: 'Replace',
      icon: Icons.find_replace,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute:
          (ref, editor) => editor?.showReplacePanel(), // Method we will create
      canExecute: (ref, editor) => editor != null,
    ),
    _createCommand(
      id: 'set_mark',
      label: 'Set Mark',
      icon: Icons.bookmark_add,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.setMark(),
    ),
    _createCommand(
      id: 'select_to_mark',
      label: 'Select to Mark',
      icon: Icons.bookmark_added,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.selectToMark(),
      canExecute: (ref, editor) {
        if (editor == null) return false;
        final editorState = ref.watch(
          codeEditorStateProvider(editor.widget.tab.id),
        );
        return editorState.hasMark;
      },
    ),
    _createCommand(
      id: 'copy',
      label: 'Copy',
      icon: Icons.content_copy,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.copy(),
    ),
    _createCommand(
      id: 'cut',
      label: 'Cut',
      icon: Icons.content_cut,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.cut(),
    ),
    _createCommand(
      id: 'paste',
      label: 'Paste',
      icon: Icons.content_paste,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.paste(),
    ),
    _createCommand(
      id: 'indent',
      label: 'Indent',
      icon: Icons.format_indent_increase,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.applyIndent(),
    ),
    _createCommand(
      id: 'outdent',
      label: 'Outdent',
      icon: Icons.format_indent_decrease,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.applyOutdent(),
    ),
    _createCommand(
      id: 'toggle_comment',
      label: 'Toggle Comment',
      icon: Icons.comment,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.toggleComments(),
    ),
    _createCommand(
      id: 'select_all',
      label: 'Select All',
      icon: Icons.select_all,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.selectAll(),
    ),
    _createCommand(
      id: 'move_line_up',
      label: 'Move Line Up',
      icon: Icons.arrow_upward,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.moveSelectionLinesUp(),
    ),
    _createCommand(
      id: 'move_line_down',
      label: 'Move Line Down',
      icon: Icons.arrow_downward,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.moveSelectionLinesDown(),
    ),
    _createCommand(
      id: 'undo',
      label: 'Undo',
      icon: Icons.undo,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.undo(),
      // REFACTORED: The canUndo/canRedo state is local to the widget,
      // so we need to watch a provider that changes when they do.
      // Watching the tabMetadataProvider works because it's updated on every keystroke.
      canExecute: (ref, editor) {
        if (editor == null) return false;
        final editorState = ref.watch(
          codeEditorStateProvider(editor.widget.tab.id),
        );
        return editorState.canUndo;
      },
    ),
    _createCommand(
      id: 'redo',
      label: 'Redo',
      icon: Icons.redo,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.redo(),
      canExecute: (ref, editor) {
        if (editor == null) return false;
        final editorState = ref.watch(
          codeEditorStateProvider(editor.widget.tab.id),
        );
        return editorState.canRedo;
      },
    ),
    _createCommand(
      id: 'show_cursor',
      label: 'Show Cursor',
      icon: Icons.center_focus_strong,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.controller.makeCursorVisible(),
    ),
    _createCommand(
      id: 'switch_language',
      label: 'Switch Language',
      icon: Icons.language,
      defaultPosition: AppCommandPositions.pluginToolbar,
      execute: (ref, editor) => editor?.showLanguageSelectionDialog(),
      canExecute: (ref, editor) => editor != null,
    ),
  ];

  Command _createCommand({
    required String id,
    required String label,
    required IconData icon,
    required CommandPosition defaultPosition,
    required FutureOr<void> Function(WidgetRef, CodeEditorMachineState?)
    execute,
    bool Function(WidgetRef, CodeEditorMachineState?)? canExecute,
  }) {
    return BaseCommand(
      id: id,
      label: label,
      icon: Icon(icon, size: 20),
      defaultPosition: defaultPosition,
      sourcePlugin: this.id,
      execute: (ref) async {
        final editorState = _getActiveEditorState(ref);
        await execute(ref, editorState);
      },
      canExecute: (ref) {
        final editorState = _getActiveEditorState(ref);
        // This is the default case for commands that don't have special conditions.
        return canExecute?.call(ref, editorState) ?? (editorState != null);
      },
    );
  }
}
