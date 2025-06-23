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
  Future<EditorTab> createTab(DocumentFile file, dynamic data) async {
    final inferredLanguageKey = CodeThemes.inferLanguageKey(file.uri);
    return CodeEditorTab(
      file: file,
      plugin: this,
      commentFormatter: CodeEditorLogic.getCommentFormatter(file.uri),
      languageKey: inferredLanguageKey,
      // Pass the initial content directly to the tab model.
      // The widget will use this on its first build.
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
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final codeTab = tab as CodeEditorTab;
    return CodeEditorMachine(
      key: ValueKey(codeTab.file.uri), // Key is still important for IndexedStack
      tab: codeTab,
      // The stateful widget now receives the initial content directly.
      initialContent: codeTab.initialContent,
      commentFormatter: codeTab.commentFormatter,
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return CustomEditorIndicator(
          controller: editingController,
          chunkController: chunkController,
          notifier: notifier,
        );
      },
    );
  }
  
  CodeEditorTab? _getTab(WidgetRef ref) {
    final tab = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab,
      ),
    );
    return tab is CodeEditorTab ? tab : null;
  }

  // Helper now reads the active controller from its dedicated provider.
  CodeLineEditingController? _getController(WidgetRef ref) {
    return ref.watch(activeCodeControllerProvider);
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    return CodeEditorTapRegion(child: const BottomToolbar());
  }

  @override
  List<Command> getCommands() => [
        _createCommand(
          id: 'save',
          label: 'Save',
          icon: Icons.save,
          defaultPosition: CommandPosition.appBar,
          execute: (ref, ctrl) async {
            if (ctrl == null) return;
            final project = ref.read(appNotifierProvider).value!.currentProject!;
            await ref.read(editorServiceProvider).saveCurrentTab(project, content: ctrl.text);
          },
          canExecute: (ref, ctrl) => ref.watch(isCurrentCodeTabDirtyProvider),
        ),
        _createCommand(
          id: 'set_mark',
          label: 'Set Mark',
          icon: Icons.bookmark_add,
          defaultPosition: CommandPosition.pluginToolbar,
          execute: (ref, ctrl) async {
            if (ctrl == null) return;
            ref.read(codeEditorMarkPositionProvider.notifier).state = ctrl.selection.base;
          },
        ),
        _createCommand(
          id: 'select_to_mark',
          label: 'Select to Mark',
          icon: Icons.bookmark_added,
          defaultPosition: CommandPosition.pluginToolbar,
          execute: _selectToMark,
          canExecute: (ref, ctrl) => ref.watch(codeEditorMarkPositionProvider) != null,
        ),
        _createCommand(id: 'copy', label: 'Copy', icon: Icons.content_copy, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.copy()),
        _createCommand(id: 'cut', label: 'Cut', icon: Icons.content_cut, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.cut()),
        _createCommand(id: 'paste', label: 'Paste', icon: Icons.content_paste, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.paste()),
        _createCommand(id: 'indent', label: 'Indent', icon: Icons.format_indent_increase, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.applyIndent()),
        _createCommand(id: 'outdent', label: 'Outdent', icon: Icons.format_indent_decrease, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.applyOutdent()),
        _createCommand(id: 'toggle_comment', label: 'Toggle Comment', icon: Icons.comment, defaultPosition: CommandPosition.pluginToolbar, execute: _toggleComments),
        _createCommand(id: 'select_all', label: 'Select All', icon: Icons.select_all, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.selectAll()),
        _createCommand(id: 'move_line_up', label: 'Move Line Up', icon: Icons.arrow_upward, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.moveSelectionLinesUp()),
        _createCommand(id: 'move_line_down', label: 'Move Line Down', icon: Icons.arrow_downward, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.moveSelectionLinesDown()),
        _createCommand(id: 'undo', label: 'Undo', icon: Icons.undo, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.undo(), canExecute: (ref, ctrl) => ref.watch(canUndoProvider)),
        _createCommand(id: 'redo', label: 'Redo', icon: Icons.redo, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.redo(), canExecute: (ref, ctrl) => ref.watch(canRedoProvider)),
        _createCommand(id: 'show_cursor', label: 'Show Cursor', icon: Icons.center_focus_strong, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => ctrl?.makeCursorVisible()),
        _createCommand(id: 'switch_language', label: 'Switch Language', icon: Icons.language, defaultPosition: CommandPosition.pluginToolbar, execute: (ref, ctrl) => _showLanguageSelectionDialog(ref), canExecute: (ref, ctrl) => _getTab(ref) is CodeEditorTab),
      ];

  Command _createCommand({
    required String id,
    required String label,
    required IconData icon,
    required CommandPosition defaultPosition,
    required FutureOr<void> Function(WidgetRef, CodeLineEditingController?) execute,
    bool Function(WidgetRef, CodeLineEditingController?)? canExecute,
  }) {
    return BaseCommand(
      id: id,
      label: label,
      icon: Icon(icon, size: 20),
      defaultPosition: defaultPosition,
      sourcePlugin: runtimeType.toString(),
      execute: (ref) async {
        final ctrl = _getController(ref);
        await execute(ref, ctrl);
      },
      canExecute: (ref) {
        final ctrl = _getController(ref);
        return canExecute?.call(ref, ctrl) ?? (ctrl != null);
      },
    );
  }

  Future<void> _toggleComments(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return;
    final tab = _getTab(ref)!;
    final formatted = tab.commentFormatter.format(
      ctrl.value,
      ctrl.options.indent,
      true,
    );
    ctrl.runRevocableOp(() => ctrl.value = formatted);
  }
  
  Future<void> _selectToMark(WidgetRef ref, CodeLineEditingController? ctrl) async {
    if (ctrl == null) return;
    final mark = ref.read(codeEditorMarkPositionProvider);
    if (mark == null) return;
    final currentPosition = ctrl.selection.base;
    final start = _comparePositions(mark, currentPosition) < 0 ? mark : currentPosition;
    final end = _comparePositions(mark, currentPosition) < 0 ? currentPosition : mark;
    ctrl.selection = CodeLineSelection(
      baseIndex: start.index,
      baseOffset: start.offset,
      extentIndex: end.index,
      extentOffset: end.offset,
    );
  }

  int _comparePositions(CodeLinePosition a, CodeLinePosition b) {
    if (a.index < b.index) return -1;
    if (a.index > b.index) return 1;
    return a.offset.compareTo(b.offset);
  }

  Future<void> _showLanguageSelectionDialog(WidgetRef ref) async {
    final BuildContext context = ref.context;
    final currentTab = _getTab(ref);
    if (currentTab == null) return;
    final selectedLanguageKey = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Select Language'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: CodeThemes.languageNameToModeMap.keys.length,
              itemBuilder: (context, index) {
                final langKey = CodeThemes.languageNameToModeMap.keys.elementAt(index);
                return ListTile(
                  title: Text(CodeThemes.formatLanguageName(langKey)),
                  onTap: () => Navigator.pop(ctx, langKey),
                );
              },
            ),
          ),
        );
      },
    );
    if (selectedLanguageKey != null) {
      final updatedTab = currentTab.copyWith(languageKey: selectedLanguageKey);
      ref.read(editorServiceProvider).updateCurrentTabModel(updatedTab);
    }
  }
}