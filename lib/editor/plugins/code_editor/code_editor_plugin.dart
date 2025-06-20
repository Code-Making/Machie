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
import 'code_editor_state.dart';
import 'code_editor_logic.dart'; // NEW IMPORT

//TODO: IMPLEMENT logging

// --------------------
//  Code Editor Plugin
// --------------------

class CodeEditorPlugin implements EditorPlugin {
  final _controllers = <String, CodeLineEditingController>{};
  // NEW: State for marks is now managed here.
  final _marks = <String, CodeLinePosition>{};

  @override
  String get name => 'Code Editor';

  @override
  Widget get icon => const Icon(Icons.code);

  @override
  final PluginSettings? settings = CodeEditorSettings();

  @override
  Widget buildSettingsUI(PluginSettings settings) {
    final editorSettings = settings as CodeEditorSettings;
    return CodeEditorSettingsUI(settings: editorSettings);
  }

  // NEW: Declare that this plugin requires raw byte data.
  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  Future<void> dispose() async {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _marks.clear();
    // print("dispose code editor");
  }

  CodeLineEditingController? getControllerForTab(EditorTab tab) {
    return _controllers[tab.file.uri];
  }

  @override
  void disposeTab(EditorTab tab) {
    final controller = _controllers.remove(tab.file.uri);
    controller?.dispose();
    _marks.remove(tab.file.uri);
  }

  @override
  bool supportsFile(DocumentFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    return CodeThemes.languageExtToNameMap.containsKey(ext);
  }

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) {
    return [];
  }

  @override
  Future<EditorTab> createTab(DocumentFile file, dynamic data) async {
    // The `data` is guaranteed to be a String here due to the default dataRequirement.
    final String content = data as String;

    final controller = CodeLineEditingController(
      spanBuilder: buildHighlightingSpan,
      codeLines: CodeLines.fromText(content),
    );
    _controllers[file.uri] = controller;
    _marks.remove(file.uri);

    final inferredLanguageKey = CodeThemes.inferLanguageKey(file.uri);
    return CodeEditorTab(
      file: file,
      plugin: this,
      commentFormatter: CodeEditorLogic.getCommentFormatter(file.uri),
      languageKey: inferredLanguageKey,
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
    // Call the main createTab method
    return createTab(file, content);
  }

  @override
  void activateTab(EditorTab tab, Ref ref) {
    if (tab is! CodeEditorTab) return;
    ref.read(bracketHighlightProvider.notifier).resetState();
  }

  @override
  void deactivateTab(EditorTab tab, Ref ref) {
    if (tab is! CodeEditorTab) return;
    ref.read(bracketHighlightProvider.notifier).resetState();
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final codeTab = tab as CodeEditorTab;
    final controller = getControllerForTab(codeTab);

    if (controller == null) {
      return const Center(
        child: Text("Error: Controller not found for this tab."),
      );
    }

    return CodeEditorMachine(
      key: ValueKey(codeTab.file.uri),
      controller: controller,
      commentFormatter: codeTab.commentFormatter,
      indicatorBuilder: (
        context,
        editingController,
        chunkController,
        notifier,
      ) {
        return CustomEditorIndicator(
          controller: editingController,
          chunkController: chunkController,
          notifier: notifier,
        );
      },
    );
  }

  // REMOVED: _buildHighlightingSpan (moved to code_editor_logic.dart)
  // REMOVED: _getCommentFormatter (moved to code_editor_logic.dart)

  @override
  List<Command> getCommands() => [
    _createCommand(
      id: 'save',
      label: 'Save',
      icon: Icons.save,
      defaultPosition: CommandPosition.appBar,
      execute: (ref, ctrl) async {
        if (ctrl == null) return;
        await ref
            .read(appNotifierProvider.notifier)
            .saveCurrentTab(content: ctrl.text);
      },
      canExecute: (ref, ctrl) => ref.watch(isCurrentCodeTabDirtyProvider),
    ),
    _createCommand(
      id: 'copy',
      label: 'Copy',
      icon: Icons.content_copy,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.copy(),
    ),
    _createCommand(
      id: 'cut',
      label: 'Cut',
      icon: Icons.content_cut,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.cut(),
    ),
    _createCommand(
      id: 'paste',
      label: 'Paste',
      icon: Icons.content_paste,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.paste(),
    ),
    _createCommand(
      id: 'indent',
      label: 'Indent',
      icon: Icons.format_indent_increase,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.applyIndent(),
    ),
    _createCommand(
      id: 'outdent',
      label: 'Outdent',
      icon: Icons.format_indent_decrease,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.applyOutdent(),
    ),
    _createCommand(
      id: 'toggle_comment',
      label: 'Toggle Comment',
      icon: Icons.comment,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _toggleComments,
    ),
    _createCommand(
      id: 'reformat',
      label: 'Reformat',
      icon: Icons.format_align_left,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _reformatDocument,
    ),
    _createCommand(
      id: 'select_brackets',
      label: 'Select Brackets',
      icon: Icons.code,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _selectBetweenBrackets,
    ),
    _createCommand(
      id: 'extend_selection',
      label: 'Extend Selection',
      icon: Icons.horizontal_rule,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _extendSelection,
    ),
    _createCommand(
      id: 'select_all',
      label: 'Select All',
      icon: Icons.select_all,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.selectAll(),
    ),
    _createCommand(
      id: 'move_line_up',
      label: 'Move Line Up',
      icon: Icons.arrow_upward,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.moveSelectionLinesUp(),
    ),
    _createCommand(
      id: 'move_line_down',
      label: 'Move Line Down',
      icon: Icons.arrow_downward,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.moveSelectionLinesDown(),
    ),
    // MODIFIED: Mark/Select commands now use the plugin's internal state.
    _createCommand(
      id: 'set_mark',
      label: 'Set Mark',
      icon: Icons.bookmark_add,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _setMarkPosition,
    ),
    _createCommand(
      id: 'select_to_mark',
      label: 'Select to Mark',
      icon: Icons.bookmark_added,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _selectToMark,
      canExecute: (ref, ctrl) {
        final tab = _getTab(ref);
        return tab != null && _marks.containsKey(tab.file.uri);
      },
    ),
    _createCommand(
      id: 'undo',
      label: 'Undo',
      icon: Icons.undo,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.undo(),
      canExecute: (ref, ctrl) => ref.watch(canUndoProvider),
    ),
    _createCommand(
      id: 'redo',
      label: 'Redo',
      icon: Icons.redo,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.redo(),
      canExecute: (ref, ctrl) => ref.watch(canRedoProvider),
    ),
    _createCommand(
      id: 'show_cursor',
      label: 'Show Cursor',
      icon: Icons.center_focus_strong,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.makeCursorVisible(),
    ),
    _createCommand(
      id: 'switch_language',
      label: 'Switch Language',
      icon: Icons.language,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => _showLanguageSelectionDialog(ref),
      canExecute: (ref, ctrl) => _getTab(ref) is CodeEditorTab,
    ),
  ];

  Command _createCommand({
    required String id,
    required String label,
    required IconData icon,
    required CommandPosition defaultPosition,
    required FutureOr<void> Function(WidgetRef, CodeLineEditingController?)
    execute,
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

  CodeLineEditingController? _getController(WidgetRef ref) {
    final tab =
        ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    return tab != null ? getControllerForTab(tab) : null;
  }

  CodeEditorTab? _getTab(WidgetRef ref) {
    final tab = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab,
      ),
    );
    return tab is CodeEditorTab ? tab : null;
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

  Future<void> _reformatDocument(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return;
    try {
      final formattedValue = _formatCodeValue(ctrl.value);
      ctrl.runRevocableOp(() {
        ctrl.value = formattedValue.copyWith(
          selection: const CodeLineSelection.zero(),
          composing: TextRange.empty,
        );
      });
      // print('Document reformatted');
    } catch (e) {
      // print('Formatting failed: ${e.toString()}');
    }
  }

  CodeLineEditingValue _formatCodeValue(CodeLineEditingValue value) {
    final buffer = StringBuffer();
    int indentLevel = 0;
    final indent = '  ';

    final codeLines = value.codeLines.toList();

    for (final line in codeLines) {
      final trimmed = line.text.trim();

      if (trimmed.startsWith('}') ||
          trimmed.startsWith(']') ||
          trimmed.startsWith(')')) {
        indentLevel = indentLevel > 0 ? indentLevel - 1 : 0;
      }

      buffer.write(indent * indentLevel);
      buffer.writeln(trimmed);

      if (trimmed.endsWith('{') ||
          trimmed.endsWith('[') ||
          trimmed.endsWith('(')) {
        indentLevel++;
      }
    }
    return CodeLineEditingValue(
      codeLines: CodeLines.fromText(buffer.toString().trim()),
      selection: value.selection,
      composing: value.composing,
    );
  }

  Future<void> _selectBetweenBrackets(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return;
    final controller = ctrl;
    final selection = controller.selection;

    if (!selection.isCollapsed) {
      // print('Selection already active');
      return;
    }

    try {
      final position = selection.base;
      final brackets = {'(': ')', '[': ']', '{': '}'};
      CodeLinePosition? start;
      CodeLinePosition? end;

      for (int offset = 0; offset <= 1; offset++) {
        final index = position.offset - offset;
        if (index >= 0 &&
            index < controller.codeLines[position.index].text.length) {
          final char = controller.codeLines[position.index].text[index];
          if (brackets.keys.contains(char) || brackets.values.contains(char)) {
            final match = _findMatchingBracket(
              controller.codeLines,
              CodeLinePosition(index: position.index, offset: index),
              brackets,
            );
            if (match != null) {
              start = CodeLinePosition(index: position.index, offset: index);
              end = match;
              break;
            }
          }
        }
      }

      if (start == null || end == null) {
        // print('No matching bracket found');
        return;
      }

      final orderedStart = _comparePositions(start, end) < 0 ? start : end;
      final orderedEnd = _comparePositions(start, end) < 0 ? end : start;

      controller.selection = CodeLineSelection(
        baseIndex: orderedStart.index,
        baseOffset: orderedStart.offset,
        extentIndex: orderedEnd.index,
        extentOffset: orderedEnd.offset + 1,
      );
      _extendSelection(ref, ctrl);
    } catch (e) {
      // print('Selection failed: ${e.toString()}');
    }
  }

  CodeLinePosition? _findMatchingBracket(
    CodeLines codeLines,
    CodeLinePosition position,
    Map<String, String> brackets,
  ) {
    final line = codeLines[position.index].text;
    final char = line[position.offset];

    final isOpen = brackets.keys.contains(char);
    final target =
        isOpen
            ? brackets[char]
            : brackets.keys.firstWhere(
              (k) => brackets[k] == char,
              orElse: () => '',
            );

    if (target?.isEmpty ?? true) return null;

    int stack = 1;
    int index = position.index;
    int offset = position.offset;
    final direction = isOpen ? 1 : -1;

    while (index >= 0 && index < codeLines.length) {
      final currentLine = codeLines[index].text;

      while (offset >= 0 && offset < currentLine.length) {
        if (index == position.index && offset == position.offset) {
          offset += direction;
          continue;
        }

        final currentChar = currentLine[offset];

        if (currentChar == char) {
          stack += 1;
        } else if (currentChar == target) {
          stack -= 1;
        }

        if (stack == 0) {
          return CodeLinePosition(index: index, offset: offset);
        }

        offset += direction;
      }

      index += direction;
      offset = direction > 0 ? 0 : (codeLines[index].text.length - 1);
    }
    return null;
  }

  Future<void> _extendSelection(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return;
    final controller = ctrl;
    final selection = controller.selection;

    final newBaseOffset = 0;
    final extentLineLength =
        controller.codeLines[selection.extentIndex].text.length;
    final newExtentOffset = extentLineLength;

    controller.selection = CodeLineSelection(
      baseIndex: selection.baseIndex,
      baseOffset: newBaseOffset,
      extentIndex: selection.extentIndex,
      extentOffset: newExtentOffset,
    );
  }

  // MODIFIED: Logic now uses the internal _marks map.
  Future<void> _setMarkPosition(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    final tab = _getTab(ref);
    if (ctrl == null || tab == null) return;
    _marks[tab.file.uri] = ctrl.selection.base;
    // We need to rebuild the widgets that depend on canExecute, which can't be done
    // easily without a provider. This is a classic state management challenge.
    // For now, this will work, but the button's enabled state won't update
    // immediately without a manual refresh of some kind.
  }

  // MODIFIED: Logic now uses the internal _marks map.
  Future<void> _selectToMark(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    final tab = _getTab(ref);
    if (ctrl == null || tab == null) return;
    final mark = _marks[tab.file.uri];
    if (mark == null) {
      // print('No mark set! Set a mark first');
      return;
    }

    try {
      final currentPosition = ctrl.selection.base;
      final start =
          _comparePositions(mark, currentPosition) < 0 ? mark : currentPosition;
      final end =
          _comparePositions(mark, currentPosition) < 0 ? currentPosition : mark;

      ctrl.selection = CodeLineSelection(
        baseIndex: start.index,
        baseOffset: start.offset,
        extentIndex: end.index,
        extentOffset: end.offset,
      );
    } catch (e) {
      // print('Selection error: ${e.toString()}');
    }
  }

  int _comparePositions(CodeLinePosition a, CodeLinePosition b) {
    if (a.index < b.index) return -1;
    if (a.index > b.index) return 1;
    return a.offset.compareTo(b.offset);
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    return CodeEditorTapRegion(child: BottomToolbar());
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
                final langKey = CodeThemes.languageNameToModeMap.keys.elementAt(
                  index,
                );
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
      ref.read(appNotifierProvider.notifier).updateCurrentTab(updatedTab);
    }
  }
}
