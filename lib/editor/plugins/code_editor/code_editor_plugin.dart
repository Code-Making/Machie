// lib/editor/plugins/code_editor/code_editor_plugin.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../command/command_widgets.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../../editor/services/editor_service.dart';
import '../../../logs/logs_provider.dart';
import '../../../project/project_models.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/toast.dart';
import '../../models/editor_command_context.dart';
import '../../models/editor_plugin_models.dart';
import '../../models/editor_tab_models.dart';
import '../../models/text_editing_capability.dart';
import '../../services/language/language_registry.dart';
import '../../services/language/language_models.dart'; // Needed for LinkSpan
import '../../tab_metadata_notifier.dart';
import 'code_editor_hot_state_adapter.dart';
import 'code_editor_hot_state_dto.dart';
import 'code_editor_models.dart';
import 'code_editor_settings_widget.dart';
import 'code_editor_widgets.dart';

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
  ) => CodeEditorSettingsUI(
    settings: settings as CodeEditorSettings,
    onChanged: onChanged,
  );
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
          final activeTab =
              ref
                  .read(appNotifierProvider)
                  .value
                  ?.currentProject
                  ?.session
                  .currentTab;
          if (activeTab is! CodeEditorTab) return false;

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
          if (activeTab is! CodeEditorTab || activeTab.id == targetTab.id) {
            return false;
          }

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
    final activeTab =
        ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (activeTab == null) return;

    final activeFile = ref.read(tabMetadataProvider)[activeTab.id]?.file;
    final repo = ref.read(projectRepositoryProvider);

    final editorState = activeTab.editorKey.currentState;
    if (activeFile == null || repo == null || editorState is! TextEditable) {
      return;
    }
    final editable = editorState as TextEditable;

    final config = Languages.getForFile(activeFile.name);
    final formatter = config.importFormatter;

    if (formatter == null) {
      MachineToast.error("Imports are not supported for ${config.name}");
      return;
    }

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

    final currentContent = await editable.getTextContent();
    final lines = currentContent.split('\n');

    int lastImportIndex = -1;
    bool alreadyExists = false;

    // --- REFACTORED: Use Parser and Heuristics ---
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;

      // 1. Check for duplicate using the Language parser
      final spans = config.parser(line);
      for (final span in spans) {
        if (span is LinkSpan) {
          // If the link target matches our path, it's a duplicate.
          // Note: This relies on the parser extracting the exact relative path string.
          if (span.target == relativePath) {
            alreadyExists = true;
            break;
          }
        }
      }
      if (alreadyExists) break;

      // 2. Find insertion point (heuristic)
      // Since regex patterns are gone from config, we check for common import keywords
      // to determine if we are still in the "import block".
      if (_isImportLine(line)) {
        lastImportIndex = i;
      } else if (!line.trim().startsWith('//') &&
          !line.trim().startsWith('/*') &&
          !line.trim().startsWith('*')) {
        // If we hit code that isn't an import or a comment, stop searching for the block end.
        // This prevents inserting imports in the middle of a function if "import" is used as a variable name.
        // (A naive optimization).
      }
    }

    if (alreadyExists) {
      MachineToast.info('Import already exists.');
      return;
    }

    final importStatement = formatter(relativePath);
    final insertionLine = lastImportIndex + 1;

    editable.insertTextAtLine(insertionLine, "$importStatement\n");
    MachineToast.info("Added: $importStatement");
  }

  /// Heuristic to detect import lines across supported languages.
  bool _isImportLine(String line) {
    final trimmed = line.trim();
    return trimmed.startsWith('import ') ||
        trimmed.startsWith('export ') ||
        trimmed.startsWith('part ') ||
        trimmed.startsWith('require(') ||
        trimmed.startsWith('#include ') ||
        trimmed.startsWith('@import ') ||
        trimmed.startsWith(r'\input') ||
        trimmed.startsWith(r'\include') ||
        trimmed.startsWith(r'\usepackage');
  }

  String? _calculateRelativePath({
    required String from,
    required String to,
    required FileHandler fileHandler,
    required WidgetRef ref,
  }) {
    try {
      final fromDirUri = fileHandler.getParentUri(from);
      final fromPath = fileHandler.getPathForDisplay(fromDirUri);
      final toPath = fileHandler.getPathForDisplay(to);

      final fromSegments =
          fromPath.split('/').where((s) => s.isNotEmpty).toList();
      final toSegments = toPath.split('/').where((s) => s.isNotEmpty).toList();

      int commonLength = 0;
      while (commonLength < fromSegments.length &&
          commonLength < toSegments.length &&
          fromSegments[commonLength] == toSegments[commonLength]) {
        commonLength++;
      }

      final upCount = fromSegments.length - commonLength;
      final upPath = List.filled(upCount, '..');
      final downPath = toSegments.sublist(commonLength);
      final relativePathSegments = [...upPath, ...downPath];

      if (relativePathSegments.isEmpty && toSegments.isNotEmpty) {
        return toSegments.last;
      }

      return relativePathSegments.join('/');
    } catch (e) {
      ref.read(talkerProvider).error("Failed to calculate relative path: $e");
      return null;
    }
  }

  // ... [Rest of the file: hotStateDtoType, adapter, createTab, buildEditor, toolbar, etc. unchanged] ...
  
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
    final codeTab = tab as CodeEditorTab;
    return CodeEditorMachine(key: codeTab.editorKey, tab: codeTab);
  }

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
      canExecute: (ref) => true,
      execute: (ref) async {
        final settings =
            ref
                    .read(effectiveSettingsProvider)
                    .pluginSettings[CodeEditorSettings]
                as CodeEditorSettings?;

        final localPath = settings?.scratchpadLocalPath;

        if (localPath != null && localPath.trim().isNotEmpty) {
          final repo = ref.read(projectRepositoryProvider);
          if (repo == null) {
            MachineToast.error(
              "A project must be open to use a local scratchpad file.",
            );
            return;
          }

          try {
            final fileUri = Uri.file(localPath.trim()).toString();
            final file = await repo.fileHandler.getFileMetadata(fileUri);

            if (file != null) {
              await ref
                  .read(appNotifierProvider.notifier)
                  .openFileInEditor(file, explicitPlugin: this);
            } else {
              MachineToast.error(
                'Could not find local scratchpad file at: $localPath',
              );
            }
          } catch (e) {
            MachineToast.error('Error opening local scratchpad file: $e');
            ref
                .read(talkerProvider)
                .error(
                  'Error opening local scratchpad file at path "$localPath"',
                  e,
                );
          }
        } else {
          final filename = settings?.scratchpadFilename ?? 'scratchpad.dart';
          final scratchpadFile = InternalAppFile(
            uri: 'internal://$filename',
            name: 'Scratchpad',
            modifiedDate: DateTime.now(),
          );
          await ref
              .read(appNotifierProvider.notifier)
              .openFileInEditor(scratchpadFile, explicitPlugin: this);
        }
      },
    ),
  ];

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
        return metadata.isDirty && metadata.file is! VirtualDocumentFile;
      },
    ),
    _createCommand(
      id: 'goto_line',
      label: 'Go to Line',
      icon: Icons.numbers,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.showGoToLineDialog(),
    ),
    _createCommand(
      id: 'select_line',
      label: 'Select Line',
      icon: Icons.horizontal_rule,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.selectOrExpandLines(),
    ),
    _createCommand(
      id: 'select_chunk',
      label: 'Select Chunk/Block',
      icon: Icons.unfold_more,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.selectCurrentChunk(),
    ),
    _createCommand(
      id: 'extend_selection',
      label: 'Extend Selection',
      icon: Icons.code,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) => editor?.extendSelection(),
      canExecute: (ref, editor) => editor != null,
    ),
    _createCommand(
      id: 'find',
      label: 'Find',
      icon: Icons.search,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute: (ref, editor) => editor?.showFindPanel(),
      canExecute: (ref, editor) => editor != null,
    ),
    _createCommand(
      id: 'find_and_replace',
      label: 'Replace',
      icon: Icons.find_replace,
      defaultPositions: [AppCommandPositions.pluginToolbar, selectionToolbar],
      execute: (ref, editor) => editor?.showReplacePanel(),
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
      execute: (ref, editor) {
        editor?.adjustSelectionIfNeeded();
        editor?.controller.applyIndent(true);
      },
    ),
    _createCommand(
      id: 'outdent',
      label: 'Outdent',
      icon: Icons.format_indent_decrease,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) {
        editor?.adjustSelectionIfNeeded();
        editor?.controller.applyOutdent();
      },
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
      execute: (ref, editor) {
        editor?.adjustSelectionIfNeeded();
        editor?.controller.moveSelectionLinesUp();
      },
    ),
    _createCommand(
      id: 'move_line_down',
      label: 'Move Line Down',
      icon: Icons.arrow_downward,
      defaultPositions: [AppCommandPositions.pluginToolbar],
      execute: (ref, editor) {
        editor?.adjustSelectionIfNeeded();
        editor?.controller.moveSelectionLinesDown();
      },
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