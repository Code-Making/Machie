// =========================================
// FILE: lib/editor/plugins/code_editor/code_editor_plugin.dart
// =========================================

// lib/editor/plugins/code_editor/code_editor_plugin.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../command/command_widgets.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../editor_tab_models.dart';
import '../plugin_models.dart';
import 'code_themes.dart';
import 'code_editor_models.dart';
import 'code_editor_widgets.dart';
import 'code_editor_settings_widget.dart';
import '../../tab_state_manager.dart';
import 'package:machine/data/dto/tab_hot_state_dto.dart'; // ADDED
import 'package:machine/data/cache/type_adapters.dart'; // ADDED
import 'package:machine/editor/plugins/code_editor/code_editor_hot_state_adapter.dart'; // ADDED
import 'package:machine/editor/plugins/code_editor/code_editor_hot_state_dto.dart'; // ADDED
import 'package:machine/editor/plugins/code_editor/code_editor_widgets.dart';
import 'code_editor_state.dart'; // <-- ADD THIS IMPORT

class CodeEditorPlugin implements EditorPlugin {
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
  String get hotStateDtoType => 'com.machine.code_editor_state';

  @override
  TypeAdapter<TabHotStateDto> get hotStateAdapter => CodeEditorHotStateAdapter();
  
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
    
    // The state object now returns a Map, so we construct the DTO here.
    final stateMap = editorState.getHotState();
    return CodeEditorHotStateDto(content: stateMap['content']);
  }
  
  @override
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}

  @override
  Future<EditorTab> createTab(DocumentFile file, dynamic data, {String? id}) async {
    // REFACTORED: The 'file' property is no longer part of the tab model.
    // The EditorService will handle associating the file with the tab's ID
    // in the metadata provider.
    return CodeEditorTab(
      plugin: this,
      initialContent: data as String,
      id: id,
    );
  }

  @override
  Future<EditorTab> createTabFromSerialization(
    Map<String, dynamic> tabJson,
    FileHandler fileHandler,
  ) async {
    // This method is now more complex as metadata is separate.
    // In a full implementation, the EditorService would handle rehydrating
    // the metadata and then calling createTab. For now, we assume we can
    // get the file and create the tab.
    final fileUri = tabJson['fileUri'] as String; // Assume fileUri is still persisted
    final file = await fileHandler.getFileMetadata(fileUri);
    if (file == null) {
      throw Exception('File not found for tab URI: $fileUri');
    }
    final content = await fileHandler.readFile(fileUri);
    return createTab(file, content);
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final codeTab = tab as CodeEditorTab;
    return CodeEditorMachine(
      key: codeTab.editorKey,
      tab: codeTab,
    );
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

  // The command definitions are now correct. They find the active
  // editor's State object and call public methods on it. The canExecute
  // logic correctly watches the tabMetadataProvider for changes in dirty status.
  @override
  List<Command> getCommands() => [
    _createCommand(
      id: 'save',
      label: 'Save',
      icon: Icons.save,
      defaultPosition: CommandPosition.appBar,
      execute: (ref, editor) => editor?.save(),
      // REFACTORED: The 'isDirty' flag is now on the metadata.
      canExecute: (ref, editor) {
        if (editor == null) return false;
        // Watch the metadata for the current tab to react to dirty state changes.
        final metadata = ref.watch(tabMetadataProvider.select((m) => m[editor.widget.tab.id]));
        return metadata?.isDirty ?? false;
      },
    ),
    _createCommand(
      id: 'set_mark',
      label: 'Set Mark',
      icon: Icons.bookmark_add,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.setMark(),
    ),
    _createCommand(
      id: 'select_to_mark',
      label: 'Select to Mark',
      icon: Icons.bookmark_added,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.selectToMark(),
canExecute: (ref, editor) {
        if (editor == null) return false;
        final editorState = ref.watch(codeEditorStateProvider(editor.widget.tab.id));
        return editorState.hasMark;
      },
      ),
    _createCommand(
      id: 'copy',
      label: 'Copy',
      icon: Icons.content_copy,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.copy(),
    ),
    _createCommand(
      id: 'cut',
      label: 'Cut',
      icon: Icons.content_cut,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.cut(),
    ),
    _createCommand(
      id: 'paste',
      label: 'Paste',
      icon: Icons.content_paste,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.paste(),
    ),
    _createCommand(
      id: 'indent',
      label: 'Indent',
      icon: Icons.format_indent_increase,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.applyIndent(),
    ),
    _createCommand(
      id: 'outdent',
      label: 'Outdent',
      icon: Icons.format_indent_decrease,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.applyOutdent(),
    ),
    _createCommand(
      id: 'toggle_comment',
      label: 'Toggle Comment',
      icon: Icons.comment,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.toggleComments(),
    ),
    _createCommand(
      id: 'select_all',
      label: 'Select All',
      icon: Icons.select_all,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.selectAll(),
    ),
    _createCommand(
      id: 'move_line_up',
      label: 'Move Line Up',
      icon: Icons.arrow_upward,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.moveSelectionLinesUp(),
    ),
    _createCommand(
      id: 'move_line_down',
      label: 'Move Line Down',
      icon: Icons.arrow_downward,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.moveSelectionLinesDown(),
    ),
    _createCommand(
      id: 'undo',
      label: 'Undo',
      icon: Icons.undo,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.undo(),
      // REFACTORED: The canUndo/canRedo state is local to the widget,
      // so we need to watch a provider that changes when they do.
      // Watching the tabMetadataProvider works because it's updated on every keystroke.
canExecute: (ref, editor) {
        if (editor == null) return false;
        final editorState = ref.watch(codeEditorStateProvider(editor.widget.tab.id));
        return editorState.canUndo;
      },
    ),
    _createCommand(
      id: 'redo',
      label: 'Redo',
      icon: Icons.redo,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.redo(),
      canExecute: (ref, editor) {
        if (editor == null) return false;
        final editorState = ref.watch(codeEditorStateProvider(editor.widget.tab.id));
        return editorState.canRedo;
      },
    ),
    _createCommand(
      id: 'show_cursor',
      label: 'Show Cursor',
      icon: Icons.center_focus_strong,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.controller.makeCursorVisible(),
    ),
    _createCommand(
      id: 'switch_language',
      label: 'Switch Language',
      icon: Icons.language,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, editor) => editor?.showLanguageSelectionDialog(),
      canExecute: (ref, editor) => editor != null,
    ),
  ];

  Command _createCommand({
    required String id,
    required String label,
    required IconData icon,
    required CommandPosition defaultPosition,
    required FutureOr<void> Function(WidgetRef, CodeEditorMachineState?) execute,
    bool Function(WidgetRef, CodeEditorMachineState?)? canExecute,
  }) {
    return BaseCommand(
      id: id,
      label: label,
      icon: Icon(icon, size: 20),
      defaultPosition: defaultPosition,
      sourcePlugin: runtimeType.toString(),
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