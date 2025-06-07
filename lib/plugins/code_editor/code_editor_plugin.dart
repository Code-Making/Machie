import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/latex.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../../file_system/file_handler.dart';
import '../../main.dart'; // For various providers
import '../../session/session_management.dart';
import '../plugin_architecture.dart';

import 'code_themes.dart'; // NEW: Import the new file

// --------------------
//  Code Editor Plugin
// --------------------

class CodeEditorPlugin implements EditorPlugin {
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
  /*
  @override
  Future<void> initializeTab(EditorTab tab, String? content) async {
    if (tab is CodeEditorTab) {
      tab.controller.codeLines = CodeLines.fromText(content ?? '');
    }
  }*/

  @override
  Future<void> dispose() async {
    // Cleanup logic here
    print("dispose code editor");
  }

  @override
  bool supportsFile(DocumentFile file) {
    // Use the map from the new CodeThemes file
    final ext = file.name.split('.').last.toLowerCase();
    return CodeThemes.languageExtToNameMap.containsKey(ext);
  }

  @override
  Future<EditorTab> createTab(DocumentFile file, String content) async {
    final controller = CodeLineEditingController(
      spanBuilder: _buildHighlightingSpan,
      codeLines: CodeLines.fromText(content ?? ''),
    );
    final inferredLanguageKey = CodeThemes.inferLanguageKey(file.uri);
    return CodeEditorTab(
      file: file,
      plugin: this,
      controller: controller,
      commentFormatter: _getCommentFormatter(file.uri),
      languageKey: inferredLanguageKey, // Store inferred key
    );
  }

  // New: Implementation for deserializing CodeEditorTab
  @override
  Future<EditorTab> createTabFromSerialization(Map<String, dynamic> tabJson, FileHandler fileHandler) async {
    final fileUri = tabJson['fileUri'] as String;
    final loadedLanguageKey = tabJson['languageKey'] as String?;
    final isDirtyOnLoad = tabJson['isDirty'] as bool? ?? false; // Load dirty state

    final file = await fileHandler.getFileMetadata(fileUri);
    if (file == null) {
      throw Exception('File not found for tab URI: $fileUri');
    }

    final content = await fileHandler.readFile(fileUri);
    final controller = CodeLineEditingController(
      spanBuilder: _buildHighlightingSpan,
      codeLines: CodeLines.fromText(content ?? ''),
    );

    return CodeEditorTab(
      file: file,
      plugin: this,
      controller: controller,
      commentFormatter: _getCommentFormatter(file.uri),
      languageKey: loadedLanguageKey ?? CodeThemes.inferLanguageKey(file.uri),
      isDirty: isDirtyOnLoad,
    );
  }


  @override
  void activateTab(EditorTab tab, NotifierProviderRef<SessionState> ref) {
    if (tab is! CodeEditorTab) return;

    // Explicit state updates for mark/highlight can still be useful here.
    ref.read(markProvider.notifier).state = null; // Clear mark when tab changes
    ref.read(bracketHighlightProvider.notifier).state = BracketHighlightState(); // Clear highlights
  }

  @override
  void deactivateTab(EditorTab tab, NotifierProviderRef<SessionState> ref) {
    if (tab is! CodeEditorTab) return;
    ref.read(markProvider.notifier).state = null; // Clear mark when tab is deactivated
    ref.read(bracketHighlightProvider.notifier).state = BracketHighlightState(); // Clear highlights
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final codeTab = tab as CodeEditorTab;

    return CodeEditorMachine(
      key: ValueKey(codeTab.file.uri), // Key remains tied to the file URI
      controller: codeTab.controller,
      commentFormatter: codeTab.commentFormatter,
      indicatorBuilder: (
          context,
          editingController,
          chunkController,
          notifier,
          ) {
        return _CustomEditorIndicator(
          controller: editingController,
          chunkController: chunkController,
          notifier: notifier,
        );
      },
    );
  }

  TextSpan _buildHighlightingSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final currentTab =
        ProviderScope.containerOf(context).read(sessionProvider).currentTab
            as CodeEditorTab;
    final highlightState = ProviderScope.containerOf(
      context,
    ).read(bracketHighlightProvider);

    final spans = <TextSpan>[];
    int currentPosition = 0;
    final highlightPositions =
        highlightState.bracketPositions
            .where((pos) => pos.index == index)
            .map((pos) => pos.offset)
            .toSet();
    //print(highlightState.bracketPositions.toString());
    void processSpan(TextSpan span) {
      final text = span.text ?? '';
      final spanStyle = span.style ?? style;
      List<int> highlightIndices = [];

      // Find highlight positions within this span
      for (var i = 0; i < text.length; i++) {
        if (highlightPositions.contains(currentPosition + i)) {
          highlightIndices.add(i);
        }
      }

      // Split span into non-highlight and highlight segments
      int lastSplit = 0;
      for (final highlightIndex in highlightIndices) {
        if (highlightIndex > lastSplit) {
          spans.add(
            TextSpan(
              text: text.substring(lastSplit, highlightIndex),
              style: spanStyle,
            ),
          );
        }
        spans.add(
          TextSpan(
            text: text[highlightIndex],
            style: spanStyle.copyWith(
              backgroundColor: Colors.yellow.withOpacity(0.3),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        lastSplit = highlightIndex + 1;
      }

      // Add remaining text
      if (lastSplit < text.length) {
        spans.add(TextSpan(text: text.substring(lastSplit), style: spanStyle));
      }

      currentPosition += text.length;

      // Process child spans
      if (span.children != null) {
        for (final child in span.children!) {
          if (child is TextSpan) {
            processSpan(child);
          }
        }
      }
    }

    processSpan(textSpan);
    return TextSpan(
      children: spans.isNotEmpty ? spans : [textSpan],
      style: style,
    );
  }

  CodeCommentFormatter _getCommentFormatter(String uri) {
    final extension = uri.split('.').last.toLowerCase();
    switch (extension) {
      case 'dart':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
      case 'tex':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '%',
        );
      default:
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
    }
  }

  @override
  List<Command> getCommands() => [
    _createCommand( // Moved this command to the top level for clarity
      id: 'save',
      label: 'Save',
      icon: Icons.save,
      defaultPosition: CommandPosition.appBar, // Default position in AppBar
      execute: (ref, _) {
        final session = ref.read(sessionProvider);
        final currentIndex = session.currentTabIndex;
        if (currentIndex != -1) {
          ref.read(sessionProvider.notifier).saveTab(currentIndex);
        }
      },
    ),
    _createCommand(
      id: 'copy',
      label: 'Copy',
      icon: Icons.content_copy,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.copy(), // Null check
    ),
    _createCommand(
      id: 'cut',
      label: 'Cut',
      icon: Icons.content_cut,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.cut(), // Null check
    ),
    _createCommand(
      id: 'paste',
      label: 'Paste',
      icon: Icons.content_paste,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.paste(), // Null check
    ),
    _createCommand(
      id: 'indent',
      label: 'Indent',
      icon: Icons.format_indent_increase,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.applyIndent(), // Null check
    ),
    _createCommand(
      id: 'outdent',
      label: 'Outdent',
      icon: Icons.format_indent_decrease,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.applyOutdent(), // Null check
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
      execute: (ref, ctrl) => ctrl?.selectAll(), // Null check
    ),
    _createCommand(
      id: 'move_line_up',
      label: 'Move Line Up',
      icon: Icons.arrow_upward,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.moveSelectionLinesUp(), // Null check
    ),
    _createCommand(
      id: 'move_line_down',
      label: 'Move Line Down',
      icon: Icons.arrow_downward,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.moveSelectionLinesDown(), // Null check
    ),
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
      canExecute: (ref, ctrl) => ref.watch(markProvider) != null,
    ),
    _createCommand(
      id: 'undo',
      label: 'Undo',
      icon: Icons.undo,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.undo(), // Null check
      canExecute: (ref, ctrl) => ref.watch(canUndoProvider),
    ),
    _createCommand(
      id: 'redo',
      label: 'Redo',
      icon: Icons.redo,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.redo(), // Null check
      canExecute: (ref, ctrl) => ref.watch(canRedoProvider),
    ),
    _createCommand(
      id: 'show_cursor',
      label: 'Show Cursor',
      icon: Icons.center_focus_strong,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.makeCursorVisible(), // Null check
    ),
    // New Command: Switch Language
    _createCommand(
      id: 'switch_language',
      label: 'Switch Language',
      icon: Icons.language,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => _showLanguageSelectionDialog(ref),
      canExecute: (ref, ctrl) => _getTab(ref) is CodeEditorTab, // Only for code editor tabs
    ),
  ];

  Command _createCommand({
    required String id,
    required String label,
    required IconData icon,
    required CommandPosition defaultPosition, // Added parameter
    required FutureOr<void> Function(WidgetRef, CodeLineEditingController?)
    execute,
    bool Function(WidgetRef, CodeLineEditingController?)? canExecute,
  }) {
    return BaseCommand(
      id: id,
      label: label,
      icon: Icon(icon, size: 20),
      defaultPosition: defaultPosition, // Pass the parameter
      sourcePlugin: this.runtimeType.toString(),
      execute: (ref) async {
        final ctrl = _getController(ref);
        await execute(ref, ctrl);
      },
      canExecute: (ref) {
        final ctrl = _getController(ref);
        return canExecute?.call(ref, ctrl) ?? true;
      },
    );
  }

  CodeLineEditingController? _getController(WidgetRef ref) {
    final tab = ref.read(sessionProvider).currentTab; // Use read instead of watch here to avoid unnecessary rebuilds if only getting controller
    return tab is CodeEditorTab ? tab.controller : null;
  }

  // Use watch for _getTab if its return value might trigger a rebuild based on tab changes,
  // but for command execution, _getController usually gets a *current* controller.
  CodeEditorTab? _getTab(WidgetRef ref) {
    final tab = ref.watch(sessionProvider).currentTab;
    return tab is CodeEditorTab ? tab : null;
  }

  // Command implementations
  Future<void> _toggleComments(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
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
    if (ctrl == null) return; // Add null check
    try {
      final formattedValue = _formatCodeValue(ctrl.value);

      ctrl.runRevocableOp(() {
        ctrl.value = formattedValue.copyWith(
          selection: const CodeLineSelection.zero(),
          composing: TextRange.empty,
        );
      });

      print('Document reformatted');
    } catch (e) {
      print('Formatting failed: ${e.toString()}');
    }
  }

  CodeLineEditingValue _formatCodeValue(CodeLineEditingValue value) {
    final buffer = StringBuffer();
    int indentLevel = 0;
    final indent = '  '; // 2 spaces

    // Convert CodeLines to a list for iteration
    final codeLines = value.codeLines.toList();

    for (final line in codeLines) {
      final trimmed = line.text.trim();

      // Handle indentation decreases
      if (trimmed.startsWith('}') ||
          trimmed.startsWith(']') ||
          trimmed.startsWith(')')) {
        indentLevel = indentLevel > 0 ? indentLevel - 1 : 0;
      }

      // Write indentation
      buffer.write(indent * indentLevel);

      // Write line content
      buffer.writeln(trimmed);

      // Handle indentation increases
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
    if (ctrl == null) return; // Add null check
    final controller = ctrl;
    final selection = controller.selection;

    if (!selection.isCollapsed) {
      print('Selection already active');
      return;
    }

    try {
      final position = selection.base;
      final brackets = {'(': ')', '[': ']', '{': '}'};
      CodeLinePosition? start;
      CodeLinePosition? end;

      // Check both left and right of cursor
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
        print('No matching bracket found');
        return;
      }

      // Order positions correctly
      final orderedStart = _comparePositions(start, end) < 0 ? start : end;
      final orderedEnd = _comparePositions(start, end) < 0 ? end : start;

      controller.selection = CodeLineSelection(
        baseIndex: orderedStart.index,
        baseOffset: orderedStart.offset,
        extentIndex: orderedEnd.index,
        extentOffset: orderedEnd.offset + 1, // Include the bracket itself
      );
      _extendSelection(ref, ctrl);
      //_showSuccess('Selected between brackets');
    } catch (e) {
      //_showError('Selection failed: ${e.toString()}');
    }
  }

  CodeLinePosition? _findMatchingBracket(
    CodeLines codeLines,
    CodeLinePosition position,
    Map<String, String> brackets,
  ) {
    final line = codeLines[position.index].text;
    final char = line[position.offset];

    // Determine if we're looking at an opening or closing bracket
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
        // Skip the original position
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

      // Move to next/previous line
      index += direction;
      offset = direction > 0 ? 0 : (codeLines[index].text.length - 1);
    }

    return null; // No matching bracket found
  }

  Future<void> _extendSelection(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
    final controller = ctrl;
    final selection = controller.selection;

    final newBaseOffset = 0;
    final baseLineLength =
        controller.codeLines[selection.baseIndex].text.length;
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

  Future<void> _setMarkPosition(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
    ref.read(markProvider.notifier).state = ctrl.selection.base;
  }

  Future<void> _selectToMark(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
    final mark = ref.read(markProvider);
    if (mark == null) {
      print('No mark set! Set a mark first');
      return;
    }

    try {
      final currentPosition = ctrl.selection.base;
      final start =
          _comparePositions(mark!, currentPosition) < 0
              ? mark!
              : currentPosition;
      final end =
          _comparePositions(mark!, currentPosition) < 0
              ? currentPosition
              : mark!;

      ctrl.selection = CodeLineSelection(
        baseIndex: start.index,
        baseOffset: start.offset,
        extentIndex: end.index,
        extentOffset: end.offset,
      );

      //_showSuccess('Selected from line ${start.index + 1} to ${end.index + 1}');
    } catch (e) {
      print('Selection error: ${e.toString()}');
    }
  }

  int _comparePositions(CodeLinePosition a, CodeLinePosition b) {
    if (a.index < b.index) return -1;
    if (a.index > b.index) return 1;
    return a.offset.compareTo(b.offset);
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    // The commands are retrieved and displayed in BottomToolbar
    return CodeEditorTapRegion(child: BottomToolbar());
  }



  

  Future<void> _showLanguageSelectionDialog(WidgetRef ref) async {
    final BuildContext? context = ref.context;

    if (context == null) {
      print('Cannot show dialog, context is null.');
      return;
    }

    final selectedLanguageKey = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Select Language'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: CodeThemes.languageNameToModeMap.keys.length, // Use from CodeThemes
              itemBuilder: (context, index) {
                final langKey = CodeThemes.languageNameToModeMap.keys.elementAt(index); // Use from CodeThemes
                return ListTile(
                  title: Text(CodeThemes.formatLanguageName(langKey)), // Use from CodeThemes
                  onTap: () => Navigator.pop(ctx, langKey),
                );
              },
            ),
          ),
        );
      },
    );

    if (selectedLanguageKey != null) {
      final sessionNotifier = ref.read(sessionProvider.notifier);
      final currentTabIndex = ref.read(sessionProvider).currentTabIndex;
      sessionNotifier.updateTabLanguageKey(currentTabIndex, selectedLanguageKey);
    }
  }

  String _formatLanguageName(String key) {
    // Simple formatting for display, e.g., 'cpp' -> 'C++', 'javascript' -> 'JavaScript'
    if (key == 'cpp') return 'C++';
    if (key == 'javascript') return 'JavaScript';
    if (key == 'typescript') return 'TypeScript';
    if (key == 'markdown') return 'Markdown';
    if (key == 'kotlin') return 'Kotlin';
    return key[0].toUpperCase() + key.substring(1);
  }
}

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeLineEditingController controller;
  final CodeCommentFormatter? commentFormatter;
  final CodeIndicatorBuilder? indicatorBuilder;
  // Removed style and wordWrap parameters; they are now observed internally

  const CodeEditorMachine({
    super.key,
    required this.controller,
    this.commentFormatter,
    this.indicatorBuilder,
  });

  @override
  ConsumerState<CodeEditorMachine> createState() => _CodeEditorMachineState();
}

class _CodeEditorMachineState extends ConsumerState<CodeEditorMachine> {
  late final FocusNode _focusNode;
  late final Map<LogicalKeyboardKey, AxisDirection> _arrowKeyDirections;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);

    _arrowKeyDirections = {
      LogicalKeyboardKey.arrowUp: AxisDirection.up,
      LogicalKeyboardKey.arrowDown: AxisDirection.down,
      LogicalKeyboardKey.arrowLeft: AxisDirection.left,
      LogicalKeyboardKey.arrowRight: AxisDirection.right,
    };

    _addControllerListeners(widget.controller);
    _updateAllStatesFromController();
  }

  @override
  void didUpdateWidget(CodeEditorMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _removeControllerListeners(oldWidget.controller);
      _addControllerListeners(widget.controller);
      _updateAllStatesFromController();
    }
  }

  @override
  void dispose() {
    _removeControllerListeners(widget.controller);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _updateAllStatesFromController() {
    ref.read(canUndoProvider.notifier).state = widget.controller.canUndo;
    ref.read(canRedoProvider.notifier).state = widget.controller.canRedo;
    ref.read(bracketHighlightProvider.notifier).handleBracketHighlight();
  }

  void _handleControllerChange() {
    ref.read(sessionProvider.notifier).markCurrentTabDirty();
    _updateAllStatesFromController();
  }

  void _addControllerListeners(CodeLineEditingController controller) {
    controller.addListener(_handleControllerChange);
  }

  void _removeControllerListeners(CodeLineEditingController controller) {
    controller.removeListener(this._handleControllerChange); // Explicitly use `this`
  }

  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    final direction = _arrowKeyDirections[event.logicalKey];
    final shiftPressed = event.isShiftPressed;

    if (direction != null) {
      if (shiftPressed) {
        widget.controller.extendSelection(direction);
      } else {
        widget.controller.moveCursor(direction);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleFocusChange(){
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          widget.controller.makeCursorVisible();
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // WATCH the CodeEditorSettings for font size/family and word wrap
    final codeEditorSettings = ref.watch(
      settingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    );

    // WATCH the current tab's languageKey here!
    final currentLanguageKey = ref.watch(sessionProvider.select(
      (s) => (s.currentTab is CodeEditorTab) ? (s.currentTab as CodeEditorTab).languageKey : null,
    ));

    return Focus(
      autofocus: false,
      canRequestFocus: true,
      onFocusChange: (bool focus) => _handleFocusChange(),
      onKey: (n, e) => _handleKeyEvent(n, e),
      child: CodeEditor(
        controller: widget.controller,
        commentFormatter: widget.commentFormatter,
        indicatorBuilder: widget.indicatorBuilder,
        // Construct CodeEditorStyle using watched settings and language key
        style: CodeEditorStyle(
          fontSize: codeEditorSettings?.fontSize ?? 12,
          fontFamily: codeEditorSettings?.fontFamily ?? 'JetBrainsMono',
          codeTheme: CodeHighlightTheme(
            theme: CodeThemes.atomOneDarkThemeData,
            languages: CodeThemes.getHighlightThemeMode(currentLanguageKey),
          ),
          // Add other style properties from your CodeEditorSettings if they exist
          // For example:
          // lineHeight: codeEditorSettings?.lineHeight,
          // selectionColor: codeEditorSettings?.selectionColor,
          // etc.
        ),
        wordWrap: codeEditorSettings?.wordWrap ?? false,
        focusNode: _focusNode,
      ),
    );
  }
}

// --------------------
//  Bracket Highlight State
// --------------------

class BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final CodeLinePosition? matchingBracketPosition;
  final Set<int> highlightedLines;

  BracketHighlightState({
    this.bracketPositions = const {},
    this.matchingBracketPosition,
    this.highlightedLines = const {},
  });
}

class BracketHighlightNotifier extends Notifier<BracketHighlightState> {
  @override
  BracketHighlightState build() {
    return BracketHighlightState();
  }

  void handleBracketHighlight() {
    final currentTab = ref.read(sessionProvider).currentTab as CodeEditorTab;
    final controller = currentTab.controller;
    final selection = controller.selection;
    if (!selection.isCollapsed) {
      state = BracketHighlightState();
      return;
    }
    final position = selection.base;
    final brackets = {'(': ')', '[': ']', '{': '}'};
    final line = controller.codeLines[position.index].text;

    Set<CodeLinePosition> newPositions = {};
    CodeLinePosition? matchPosition;
    Set<int> newHighlightedLines = {};

    final index = position.offset;
    if (index >= 0 && index < line.length) {
      final char = line[index];
      if (brackets.keys.contains(char) || brackets.values.contains(char)) {
        matchPosition = _findMatchingBracket(
          controller.codeLines,
          position,
          brackets,
        );
        if (matchPosition != null) {
          newPositions.add(position);
          newPositions.add(matchPosition);
          newHighlightedLines.add(position.index);
          newHighlightedLines.add(matchPosition.index);
        }
      }
    }
    //print("highlighting for realsies "+newPositions.toString());

    state = BracketHighlightState(
      bracketPositions: newPositions,
      matchingBracketPosition: matchPosition,
      highlightedLines: newHighlightedLines,
    );
  }

  CodeLinePosition? _findMatchingBracket(
    CodeLines codeLines,
    CodeLinePosition position,
    Map<String, String> brackets,
  ) {
    final line = codeLines[position.index].text;
    final char = line[position.offset];

    // Determine if we're looking at an opening or closing bracket
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
        // Skip the original position
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

      // Move to next/previous line
      index += direction;
      offset = direction > 0 ? 0 : (codeLines[index].text.length - 1);
    }

    return null; // No matching bracket found
  }
}

// --------------------
//  Custom Line Number Widget
// --------------------

class _CustomEditorIndicator extends ConsumerWidget {
  final CodeLineEditingController controller;
  final CodeChunkController chunkController;
  final CodeIndicatorValueNotifier notifier;

  const _CustomEditorIndicator({
    required this.controller,
    required this.chunkController,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightState = ref.watch(bracketHighlightProvider);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // Absorb taps
      child: Row(
        children: [
          _CustomLineNumberWidget(
            controller: controller,
            notifier: notifier,
            highlightedLines: highlightState.highlightedLines,
          ),
          DefaultCodeChunkIndicator(
            width: 20,
            controller: chunkController,
            notifier: notifier,
          ),
        ],
      ),
    );
  }
}

class _CustomLineNumberWidget extends ConsumerWidget {
  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final Set<int> highlightedLines;

  const _CustomLineNumberWidget({
    required this.controller,
    required this.notifier,
    required this.highlightedLines,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<CodeIndicatorValue?>(
      valueListenable: notifier,
      builder: (context, value, child) {
        return DefaultCodeLineNumber(
          controller: controller,
          notifier: notifier,
          textStyle: TextStyle(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
            fontSize: 12,
          ),
          focusedTextStyle: TextStyle(
            color: theme.colorScheme.secondary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          customLineIndex2Text: (index) {
            final lineNumber = (index + 1).toString();
            return highlightedLines.contains(index)
                ? '➤$lineNumber'
                : lineNumber;
          },
        );
      },
    );
  }
}

// --------------------
//  Code Editor Settings
// --------------------
class CodeEditorSettings extends PluginSettings {
  bool wordWrap;
  double fontSize;
  String fontFamily;

  CodeEditorSettings({
    this.wordWrap = false,
    this.fontSize = 14,
    this.fontFamily = 'JetBrainsMono',
  });

  @override
  Map<String, dynamic> toJson() => {
    'wordWrap': wordWrap,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
  };

  @override
  void fromJson(Map<String, dynamic> json) {
    wordWrap = json['wordWrap'] ?? false;
    fontSize = json['fontSize']?.toDouble() ?? 14;
    fontFamily = json['fontFamily'] ?? 'JetBrainsMono';
  }

  CodeEditorSettings copyWith({
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
  }) {
    return CodeEditorSettings(
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

class CodeEditorSettingsUI extends ConsumerStatefulWidget {
  final CodeEditorSettings settings;

  const CodeEditorSettingsUI({super.key, required this.settings});

  @override
  ConsumerState<CodeEditorSettingsUI> createState() =>
      _CodeEditorSettingsUIState();
}

class _CodeEditorSettingsUIState extends ConsumerState<CodeEditorSettingsUI> {
  late CodeEditorSettings _currentSettings;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Word Wrap'),
          value: _currentSettings.wordWrap,
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(wordWrap: value)),
        ),
        Slider(
          value: _currentSettings.fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          label: 'Font Size: ${_currentSettings.fontSize.round()}',
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(fontSize: value)),
        ),
        DropdownButtonFormField<String>(
          value: _currentSettings.fontFamily,
          items: const [
            DropdownMenuItem(
              value: 'JetBrainsMono',
              child: Text('JetBrains Mono'),
            ),
            DropdownMenuItem(value: 'FiraCode', child: Text('Fira Code')),
            // DropdownMenuItem(value: 'SourceSans3', child: Text('Source Sans')),
            DropdownMenuItem(value: 'RobotoMono', child: Text('Roboto Mono')),
          ],
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(fontFamily: value)),
        ),
      ],
    );
  }

  // In _CodeEditorSettingsUIState
  void _updateSettings(CodeEditorSettings newSettings) {
    setState(() => _currentSettings = newSettings);
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }
}