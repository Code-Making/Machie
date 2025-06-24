// lib/editor/plugins/code_editor/code_editor_plugin.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../command/command_widgets.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../editor/services/editor_service.dart';
import '../../editor_tab_models.dart';
import '../plugin_models.dart';
import 'code_themes.dart';
import 'code_editor_models.dart';
import 'code_editor_widgets.dart';
import 'code_editor_settings_widget.dart';
import 'code_editor_logic.dart';
import '../../tab_state_manager.dart';

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
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}

  @override
  Future<EditorTab> createTab(DocumentFile file, dynamic data) async {
    return CodeEditorTab(
      file: file,
      plugin: this,
      initialContent: data as String,
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
    return createTab(file, content);
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final codeTab = tab as CodeEditorTab;
    return CodeEditorMachine(
      // The GlobalKey from the tab model is passed to the widget's key property.
      // This is how we can access its state later.
      key: codeTab.editorKey,
      tab: codeTab,
    );
  }
  
  /// Helper to find the state of the currently active editor widget.
  CodeEditorMachineState? _getActiveEditorState(WidgetRef ref) {
    final tab = ref.watch(appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab,
    ));
    // Ensure the current tab is a CodeEditorTab before trying to access its state.
    if (tab is! CodeEditorTab) return null;
    // The key is generic, so the state is of type State<StatefulWidget>?
    // We safely cast it to the specific State type we need.
    return tab.editorKey.currentState as CodeEditorMachineState?;
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    return CodeEditorTapRegion(child: const BottomToolbar());
  }

  // The command definitions are now much cleaner. They find the active
  // editor's State object and call public methods directly on it.
  @override
  List<Command> getCommands() => [
        _createCommand(
          id: 'save',
          label: 'Save',
          icon: Icons.save,
          defaultPosition: CommandPosition.appBar,
          execute: (ref, editor) => editor?.save(),
          canExecute: (ref, editor) => editor?.isDirty ?? false,
        ),
        _createCommand(id: 'set_mark', label: 'Set Mark', icon: Icons.bookmark_add, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.setMark()),
        _createCommand(id: 'select_to_mark', label: 'Select to Mark', icon: Icons.bookmark_added, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.selectToMark(), canExecute: (ref, editor) => editor?.hasMark ?? false),
        _createCommand(id: 'copy', label: 'Copy', icon: Icons.content_copy, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.copy()),
        _createCommand(id: 'cut', label: 'Cut', icon: Icons.content_cut, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.cut()),
        _createCommand(id: 'paste', label: 'Paste', icon: Icons.content_paste, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.paste()),
        _createCommand(id: 'indent', label: 'Indent', icon: Icons.format_indent_increase, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.applyIndent()),
        _createCommand(id: 'outdent', label: 'Outdent', icon: Icons.format_indent_decrease, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.applyOutdent()),
        _createCommand(id: 'toggle_comment', label: 'Toggle Comment', icon: Icons.comment, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.toggleComments()),
        _createCommand(id: 'select_all', label: 'Select All', icon: Icons.select_all, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.selectAll()),
        _createCommand(id: 'move_line_up', label: 'Move Line Up', icon: Icons.arrow_upward, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.moveSelectionLinesUp()),
        _createCommand(id: 'move_line_down', label: 'Move Line Down', icon: Icons.arrow_downward, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.moveSelectionLinesDown()),
        _createCommand(id: 'undo', label: 'Undo', icon: Icons.undo, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.undo(), canExecute: (ref, editor) => editor?.canUndo ?? false),
        _createCommand(id: 'redo', label: 'Redo', icon: Icons.redo, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.redo(), canExecute: (ref, editor) => editor?.canRedo ?? false),
        _createCommand(id: 'show_cursor', label: 'Show Cursor', icon: Icons.center_focus_strong, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.controller.makeCursorVisible()),
        _createCommand(id: 'switch_language', label: 'Switch Language', icon: Icons.language, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, editor) => editor?.showLanguageSelectionDialog(), canExecute: (ref, editor) => editor != null),
      ];

  Command _createCommand({
    required String id,
    required String label,
    required IconData icon,
    required CommandPosition defaultPosition,
    // The execute function now receives the specific State type.
    required FutureOr<void> Function(WidgetRef, CodeEditorMachineState?) execute,
    // The canExecute function also receives the specific State type.
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
        // The canExecute function needs to be reactive. Since the editor state
        // itself isn't a provider, we watch the metadata provider which gets
        // updated by the editor state. This triggers a rebuild of the button.
        ref.watch(tabMetadataProvider);
        return canExecute?.call(ref, editorState) ?? (editorState != null);
      },
    );
  }
}