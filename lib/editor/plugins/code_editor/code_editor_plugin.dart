import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../command/command_widgets.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../settings/settings_notifier.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../models/editor_command_context.dart';
import '../../../editor/services/editor_service.dart';
import '../../models/text_editing_capability.dart';
import '../../../logs/logs_provider.dart';
import '../../../project/project_models.dart';
import '../../../utils/toast.dart';
import '../../models/editor_tab_models.dart';
import '../../tab_metadata_notifier.dart';
import '../../models/editor_plugin_models.dart';
import 'code_editor_hot_state_adapter.dart';
import 'code_editor_hot_state_dto.dart';
import 'code_editor_models.dart';
import 'code_editor_settings_widget.dart';
import 'code_editor_widgets.dart';
import '../../../utils/code_themes.dart';

import 'package:machine/editor/services/language/language_models.dart';
import 'package:machine/editor/services/language/language_registry.dart';

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
  Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) =>
      CodeEditorSettingsUI(settings: settings as CodeEditorSettings, onChanged: onChanged);
  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  Type? get hotStateDtoRuntimeType => CodeEditorHotStateDto;

  @override
  Widget wrapCommandToolbar(Widget toolbar) {
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
    return Languages.isSupported(file.name);
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
          // 1. Must be in Code Editor
          final activeTab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
          if (activeTab is! CodeEditorTab) return false;

          // 2. Active file must support import formatting
          final activeFile = ref.read(tabMetadataProvider)[activeTab.id]?.file;
          if (activeFile == null) return false;

          final config = Languages.getForFile(activeFile.name);
          return config.importFormatter != null;
        },
        executeFor: (ref, item) async {
          await _executeAddImport(ref, item);
        },
      ),
    ];
  }

  @override
  List<TabContextCommand> getTabContextMenuCommands() {
    return [
      BaseTabContextCommand(
        id: 'add_import_from_tab',
        label: 'Add Import From Tab',
        icon: const Icon(Icons.arrow_downward, size: 20),
        sourcePlugin: id,
        canExecuteFor: (ref, activeTab, targetTab) {
          if (activeTab is! CodeEditorTab || activeTab.id == targetTab.id) return false;

          final activeFile = ref.read(tabMetadataProvider)[activeTab.id]?.file;
          if (activeFile == null) return false;

          final config = Languages.getForFile(activeFile.name);
          return config.importFormatter != null;
        },
        executeFor: (ref, activeTab, targetTab) async {
          final targetFile = ref.read(tabMetadataProvider)[targetTab.id]?.file;
          if (targetFile != null) {
            await _executeAddImport(ref, targetFile);
          }
        },
      ),
    ];
  }
  
  Future<void> _executeAddImport(WidgetRef ref, DocumentFile targetFile) async {
    final activeTab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (activeTab == null) return;

    final activeFile = ref.read(tabMetadataProvider)[activeTab.id]?.file;
    final repo = ref.read(projectRepositoryProvider);
    
    // Get the TextEditable interface
    final editorState = activeTab.editorKey.currentState;
    if (activeFile == null || repo == null || editorState is! TextEditable) {
      return;
    }
    final editable = editorState as TextEditable;

    // 1. Get Configuration
    final config = Languages.getForFile(activeFile.name);
    final formatter = config.importFormatter;
    
    if (formatter == null) {
      MachineToast.error("Imports are not supported for ${config.name}");
      return;
    }

    // 2. Calculate Relative Path
    final relativePath = _calculateRelativePath(
      from: activeFile.uri,
      to: targetFile.uri,
      fileHandler: repo.fileHandler,
      ref: ref,
    );

    if (relativePath == null) {
      MachineToast.error('Could not calculate relative path.');
      return;
    }

    // 3. Check for Duplicates & Find Insertion Point
    final currentContent = await editable.getTextContent();
    final lines = currentContent.split('\n');
    
    int lastImportIndex = -1;
    bool alreadyExists = false;

    // Iterate lines to find import block and check duplicates
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // Check patterns defined in the language config
      for (final pattern in config.importPatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          lastImportIndex = i; // Track the last known import line
          
          // Check if this import matches our target path
          // Note: This is a simplified string check. 
          // 'group(1)' is assumed to be the path based on our Regex convention.
          if (match.groupCount >= 1) {
            final existingPath = match.group(1);
            if (existingPath == relativePath) {
              alreadyExists = true;
            }
          }
        }
      }
      if (alreadyExists) break;
    }

    if (alreadyExists) {
      MachineToast.info('Import already exists.');
      return;
    }

    // 4. Insert
    final importStatement = formatter(relativePath);
    final insertionLine = lastImportIndex + 1;
    
    editable.insertTextAtLine(insertionLine, "$importStatement\n");
    MachineToast.info("Added: $importStatement");
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

      final fromSegments =
          fromPath.split('/').where((s) => s.isNotEmpty).toList();
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
    String? initialLanguageId;

    if (initData.hotState is CodeEditorHotStateDto) {
      final hotState = initData.hotState as CodeEditorHotStateDto;
      cachedContent = hotState.content;
      initialLanguageId = hotState.languageId;
    } 

    return CodeEditorTab(
      plugin: this,
      initialContent: initialContent,
      cachedContent: cachedContent,
      initialLanguageId: initialLanguageId,
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
    return tab.editorKey.currentState;
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
          // No need to check for a project, the scratchpad is global.
          canExecute: (ref) => true,
          execute: (ref) async {
            // Read settings to determine which scratchpad to open
            final settings = ref
                .read(effectiveSettingsProvider)
                .pluginSettings[CodeEditorSettings] as CodeEditorSettings?;

            final localPath = settings?.scratchpadLocalPath;

            if (localPath != null && localPath.trim().isNotEmpty) {
              // A local file path is configured, try to open it.
              final repo = ref.read(projectRepositoryProvider);
              if (repo == null) {
                MachineToast.error(
                    "A project must be open to use a local scratchpad file.");
                return;
              }

              try {
                // FileHandler works with URIs. Convert the file path to a URI string.
                // Uri.file() correctly handles platform-specific path formats.
                final fileUri = Uri.file(localPath.trim()).toString();
                final file = await repo.fileHandler.getFileMetadata(fileUri);

                if (file != null) {
                  await ref
                      .read(appNotifierProvider.notifier)
                      .openFileInEditor(file, explicitPlugin: this);
                } else {
                  MachineToast.error(
                      'Could not find local scratchpad file at: $localPath');
                }
              } catch (e) {
                MachineToast.error('Error opening local scratchpad file: $e');
                ref.read(talkerProvider).error(
                    'Error opening local scratchpad file at path "$localPath"',
                    e);
              }
            } else {
              // No local file, use the internal scratchpad.
              final filename =
                  settings?.scratchpadFilename ?? 'scratchpad.dart';

              final scratchpadFile = InternalAppFile(
                uri: 'internal://$filename',
                name: 'Scratchpad',
                modifiedDate: DateTime.now(), // Placeholder date
              );

              await ref
                  .read(appNotifierProvider.notifier)
                  .openFileInEditor(scratchpadFile, explicitPlugin: this);
            }
          },
        ),
  ];

  // The command definitions are now correct. They find the active
  // editor's State object and call public methods on it. The canExecute
  // logic correctly watches the tabMetadataProvider for changes in dirty status.
  @override
  List<Command> getCommands(Ref ref) => [
    BaseCommand(
      id: 'save',
      label: 'Save',
      icon: const Icon(Icons.save),
      defaultPositions: [AppCommandPositions.appBar],
      sourcePlugin: id,
      execute: (ref) async => ref.read(editorServiceProvider).saveCurrentTab(),
      canExecute: (ref) {
        final currentTabId = ref.watch(
          appNotifierProvider.select(
            (s) => s.value?.currentProject?.session.currentTab?.id,
          ),
        );
        if (currentTabId == null) return false;

        final metadata = ref.watch(
          tabMetadataProvider.select((m) => m[currentTabId]),
        );
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
      execute: (ref, editor) {editor?.adjustSelectionIfNeeded(); editor?.controller.applyIndent(true);},
    ),
    _createCommand(
      id: 'outdent',
      label: 'Outdent',
      icon: Icons.format_indent_decrease,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) {editor?.adjustSelectionIfNeeded(); editor?.controller.applyOutdent();},
    ),
    _createCommand(
      id: 'toggle_comment',
      label: 'Toggle Comment',
      icon: Icons.comment,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute: (ref, editor) => editor?.toggleComments(),
    ),
    _createCommand(
      id: 'delete_comment_text',
      label: 'Delete Comment Text',
      icon: Icons.delete_sweep_outlined,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute: (ref, editor) => editor?.deleteCommentText(),
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
      execute: (ref, editor) {editor?.adjustSelectionIfNeeded(); editor?.controller.moveSelectionLinesUp();},
    ),
    _createCommand(
      id: 'move_line_down',
      label: 'Move Line Down',
      icon: Icons.arrow_downward,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) {editor?.adjustSelectionIfNeeded(); editor?.controller.moveSelectionLinesDown();},
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
