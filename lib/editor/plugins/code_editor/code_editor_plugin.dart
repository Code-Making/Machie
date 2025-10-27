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
import '../../../data/cache/hot_state_cache_service.dart';
import '../../../project/project_models.dart';
import '../../../editor/plugins/editor_command_context.dart'; // <-- IMPORT NEW CONTEXT
import '../../../editor/services/editor_service.dart';
import '../../../editor/services/text_editing_capability.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../utils/toast.dart'; // <-- FIX: ADDED IMPORT
import '../../../logs/logs_provider.dart'; // <-- FIX: ADDED IMPORT


class CodeEditorPlugin extends EditorPlugin with TextEditablePlugin {
  static const String pluginId = 'com.machine.code_editor';
  static const String hotStateId = 'com.machine.code_editor_state';
  static const CommandPosition selectionToolbar = CommandPosition(
    id: 'com.machine.code_editor.selection_toolbar',
    label: 'Code Selection Toolbar',
    icon: Icons.edit_attributes,
  );
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
  int get priority => 0;

  @override
  bool supportsFile(DocumentFile file) {
    final ext = file.name.split('.').lastOrNull?.toLowerCase();
    if (ext == null) return false;
    
    // Check against the map of known language extensions.
    return CodeThemes.languageExtToNameMap.containsKey(ext);
  }

  /// As the fallback editor for text files, this should always return true.
  /// If no specialized plugin claims the content, this one will.
  @override
  bool canOpenFileContent(String content, DocumentFile file) {
    return true;
  }

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) {
    return [
      BaseFileContextCommand(
        id: 'add_import',
        label: 'Add Import',
        icon: const Icon(Icons.arrow_downward),
        sourcePlugin: id,
        canExecuteFor: (ref, item) {
          // ... (canExecuteFor logic is unchanged)
          if (!supportsFile(item)) {
            return false;
          }
          final activeTab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
          if (activeTab is! CodeEditorTab) {
            return false;
          }
          final activeFile = ref.read(tabMetadataProvider)[activeTab.id]?.file;
          return activeFile != null && supportsFile(activeFile);
        },
        // v-- THIS is the updated logic --v
        executeFor: (ref, item) async {
          final activeTab = ref.read(appNotifierProvider).value!.currentProject!.session.currentTab!;
          final activeFile = ref.read(tabMetadataProvider)[activeTab.id]!.file;
          final repo = ref.read(projectRepositoryProvider)!;
          final activeEditorState = activeTab.editorKey.currentState;

          if (activeEditorState == null || activeEditorState is! TextEditable) {
            MachineToast.error('Active editor does not support text edits.');
            return;
          }
          final editableState = activeEditorState as TextEditable;

          // 1. Get the full text content using the new interface method
          final currentContent = await editableState.getTextContent();
          final lines = currentContent.split('\n');

          // 2. Calculate the relative path for the import
          final relativePath = _calculateRelativePath(
            from: activeFile.uri,
            to: item.uri,
            fileHandler: repo.fileHandler,
            ref: ref,
          );

          if (relativePath == null) {
            MachineToast.error('Could not calculate relative path.');
            return;
          }

          // 3. Check if the import already exists
          final importStatement = "import '$relativePath';";
          if (lines.any((line) => line.trim() == importStatement)) {
            MachineToast.info('Import already exists.');
            return;
          }

          // 4. Find the correct line to insert the new import
          final importRegex = RegExp(r"^\s*import\s+['].*?['];");
          int lastImportLineIndex = -1;
          for (int i = 0; i < lines.length; i++) {
            if (importRegex.hasMatch(lines[i])) {
              lastImportLineIndex = i;
            }
          }
          final insertionLine = lastImportLineIndex + 1;

          // 5. Use the new, specific interface method to perform the insertion
          editableState.insertTextAtLine(insertionLine, "$importStatement\n");
        },
      ),
    ];
  } 
  
  // v-- REPLACED with FileHandler-only implementation --v
  String? _calculateRelativePath({
    required String from,
    required String to,
    required FileHandler fileHandler,
    required WidgetRef ref, // Pass ref for logging
  }) {
    try {
      final fromDirUri = fileHandler.getParentUri(from);
      
      // Use getPathForDisplay to get clean, comparable path strings
      final fromPath = fileHandler.getPathForDisplay(fromDirUri);
      final toPath = fileHandler.getPathForDisplay(to);

      final fromSegments = fromPath.split('/').where((s) => s.isNotEmpty).toList();
      final toSegments = toPath.split('/').where((s) => s.isNotEmpty).toList();

      // Find the common ancestor path
      int commonLength = 0;
      while (commonLength < fromSegments.length &&
             commonLength < toSegments.length &&
             fromSegments[commonLength] == toSegments[commonLength]) {
        commonLength++;
      }

      // Calculate how many levels to go up ('..')
      final upCount = fromSegments.length - commonLength;
      final upPath = List.filled(upCount, '..');

      // Get the remaining path to go down
      final downPath = toSegments.sublist(commonLength);

      final relativePathSegments = [...upPath, ...downPath];
      
      // Handle case where files are in the same directory
      if (relativePathSegments.isEmpty && toSegments.isNotEmpty) {
        return toSegments.last;
      }

      return relativePathSegments.join('/');
    } catch (e) {
      ref.read(talkerProvider).error("Failed to calculate relative path: $e");
      return null;
    }
  }
  
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
  List<CommandPosition> getCommandPositions() {
    return [selectionToolbar];
  }

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    final stringContent = initData.initialContent as EditorContentString;
    final initialContent = stringContent.content;
    final initialBaseContentHash = initData.baseContentHash;
    String? cachedContent;
    String? initialLanguageKey;

    if (initData.hotState is CodeEditorHotStateDto) {
      final hotState = initData.hotState as CodeEditorHotStateDto;
      cachedContent = hotState.content;
      initialLanguageKey = hotState.languageKey;
    }

    return CodeEditorTab(
      plugin: this,
      initialContent: initialContent,
      cachedContent: cachedContent,
      initialLanguageKey: initialLanguageKey,
      initialBaseContentHash: initialBaseContentHash,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    // We must ensure the tab is the correct concrete type.
    final codeTab = tab as CodeEditorTab;
    
    // The key is now accessed directly from the correctly-typed tab model.
    // No casting is needed, and the type is correct.
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

  @override
  List<Command> getAppCommands() => [
    BaseCommand(
      id: 'open_scratchpad',
      label: 'Open Scratchpad',
      icon: const Icon(Icons.edit_note),
      defaultPositions: [AppCommandPositions.appBar],
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

        final hotStateCacheService = ref.read(hotStateCacheServiceProvider);
        final codeEditorPlugin = this;
        final scratchpadFile = VirtualDocumentFile(
          uri: 'scratchpad://${project.id}',
          name: 'Scratchpad',
        );

        // Try to load cached DTO.
        final cachedDto = await hotStateCacheService.getTabState(
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
    BaseCommand(
      id: 'save',
      label: 'Save',
      icon: const Icon(Icons.save),
      defaultPositions: [AppCommandPositions.appBar],
      sourcePlugin: id,
      execute: (ref) async => ref.read(editorServiceProvider).saveCurrentTab(),
      canExecute: (ref) {
        final currentTabId = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.id));
        if (currentTabId == null) return false;
        
        final metadata = ref.watch(tabMetadataProvider.select((m) => m[currentTabId]));
        if (metadata == null) return false;

        // THE FIX: The command can only execute if the tab is dirty AND it's not a virtual file.
        return metadata.isDirty && metadata.file is! VirtualDocumentFile;
      },
    ),
    _createCommand(
      id: 'goto_line',
      label: 'Go to Line',
      icon: Icons.numbers, // Or Icons.line_weight
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute:
          (ref, editor) =>
              editor?.showGoToLineDialog(), // Method we will create
    ),
    _createCommand(
      id: 'select_line',
      label: 'Select Line',
      icon:
          Icons.horizontal_rule, // A fitting icon for selecting a line segment
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute:
          (ref, editor) =>
              editor?.selectOrExpandLines(), // Method to be created
    ),
    _createCommand(
      id: 'select_chunk',
      label: 'Select Chunk/Block',
      icon: Icons.unfold_more, // A fitting icon for selecting a code block
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute:
          (ref, editor) => editor?.selectCurrentChunk(), // Method to be created
    ),
    _createCommand(
      id: 'extend_selection',
      label: 'Extend Selection',
      icon: Icons.code, // A different icon to distinguish from 'Select All'
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute:
          (ref, editor) => editor?.extendSelection(), // Method we will create
      canExecute: (ref, editor) => editor != null,
    ),
    _createCommand(
      id: 'find',
      label: 'Find',
      icon: Icons.search,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute:
          (ref, editor) => editor?.showFindPanel(), // Method we will create
      canExecute: (ref, editor) => editor != null,
    ),
    _createCommand(
      id: 'find_and_replace',
      label: 'Replace',
      icon: Icons.find_replace,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute:
          (ref, editor) => editor?.showReplacePanel(), // Method we will create
      canExecute: (ref, editor) => editor != null,
    ),
    _createCommand(
      id: 'set_mark',
      label: 'Set Mark',
      icon: Icons.bookmark_add,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.setMark(),
    ),
    BaseCommand(
      id: 'select_to_mark',
      label: 'Select to Mark',
      icon: const Icon(Icons.bookmark_added),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.selectToMark(),
      canExecute: (ref) {
        final context = ref.watch(activeCommandContextProvider);
        return (context is CodeEditorCommandContext) && context.hasMark;
      },
    ),
    _createCommand(
      id: 'copy',
      label: 'Copy',
      icon: Icons.content_copy,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute: (ref, editor) => editor?.controller.copy(),
    ),
    _createCommand(
      id: 'cut',
      label: 'Cut',
      icon: Icons.content_cut,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute: (ref, editor) => editor?.controller.cut(),
    ),
    _createCommand(
      id: 'paste',
      label: 'Paste',
      icon: Icons.content_paste,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute: (ref, editor) => editor?.controller.paste(),
    ),
    _createCommand(
      id: 'indent',
      label: 'Indent',
      icon: Icons.format_indent_increase,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.controller.applyIndent(true),
    ),
    _createCommand(
      id: 'outdent',
      label: 'Outdent',
      icon: Icons.format_indent_decrease,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.controller.applyOutdent(),
    ),
    _createCommand(
      id: 'toggle_comment',
      label: 'Toggle Comment',
      icon: Icons.comment,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute: (ref, editor) => editor?.toggleComments(),
    ),
    _createCommand(
      id: 'select_all',
      label: 'Select All',
      icon: Icons.select_all,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.controller.selectAll(),
    ),
    _createCommand(
      id: 'move_line_up',
      label: 'Move Line Up',
      icon: Icons.arrow_upward,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.controller.moveSelectionLinesUp(),
    ),
    _createCommand(
      id: 'move_line_down',
      label: 'Move Line Down',
      icon: Icons.arrow_downward,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.controller.moveSelectionLinesDown(),
    ),
    BaseCommand(
      id: 'undo',
      label: 'Undo',
      icon: const Icon(Icons.undo),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.undo(),
      canExecute: (ref) {
        final context = ref.watch(activeCommandContextProvider);
        return (context is CodeEditorCommandContext) && context.canUndo;
      },
    ),
    BaseCommand(
      id: 'redo',
      label: 'Redo',
      icon: const Icon(Icons.redo),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.redo(),
      canExecute: (ref) {
        final context = ref.watch(activeCommandContextProvider);
        return (context is CodeEditorCommandContext) && context.canRedo;
      },
    ),
    _createCommand(
      id: 'show_cursor',
      label: 'Show Cursor',
      icon: Icons.center_focus_strong,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.controller.makeCursorVisible(),
    ),
    _createCommand(
      id: 'switch_language',
      label: 'Switch Language',
      icon: Icons.language,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.showLanguageSelectionDialog(),
      canExecute: (ref, editor) => editor != null,
    ),
  ];

  Command _createCommand({
    required String id,
    required String label,
    required IconData icon,
    required List<CommandPosition> defaultPositions,
    required FutureOr<void> Function(WidgetRef, CodeEditorMachineState?)
    execute,
    bool Function(WidgetRef, CodeEditorMachineState?)? canExecute,
  }) {
    return BaseCommand(
      id: id,
      label: label,
      icon: Icon(icon, size: 20),
      defaultPositions: defaultPositions,
      sourcePlugin: this.id,
      execute: (ref) async {
        final editorState = _getActiveEditorState(ref);
        await execute(ref, editorState);
      },
      canExecute: (ref) {
        final editorState = _getActiveEditorState(ref);
        return canExecute?.call(ref, editorState) ?? (editorState != null);
      },
    );
  }
}
