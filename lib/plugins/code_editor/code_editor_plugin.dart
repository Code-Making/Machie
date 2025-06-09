import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../../app/app_notifier.dart';
import '../../project/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import '../../session/session_models.dart';
import '../plugin_architecture.dart';
import 'code_themes.dart';

// --------------------
// Code Editor Plugin Providers
// --------------------

final bracketHighlightProvider =
    NotifierProvider<BracketHighlightNotifier, BracketHighlightState>(
      BracketHighlightNotifier.new,
    );

final canUndoProvider = StateProvider<bool>((ref) => false);
final canRedoProvider = StateProvider<bool>((ref) => false);
final markProvider = StateProvider<CodeLinePosition?>((ref) => null);

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

  @override
  Future<void> dispose() async {
    print("dispose code editor");
  }

  @override
  bool supportsFile(DocumentFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    return CodeThemes.languageExtToNameMap.containsKey(ext);
  }
  
  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item){
      return [];
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
      languageKey: inferredLanguageKey,
    );
  }

  @override
  Future<EditorTab> createTabFromSerialization(Map<String, dynamic> tabJson, FileHandler fileHandler) async {
    final fileUri = tabJson['fileUri'] as String;
    final loadedLanguageKey = tabJson['languageKey'] as String?;
    final isDirtyOnLoad = tabJson['isDirty'] as bool? ?? false;

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


  // CORRECTED: Update signature to use `Ref`
  @override
  void activateTab(EditorTab tab, Ref ref) {
    if (tab is! CodeEditorTab) return;
    ref.read(markProvider.notifier).state = null;
    ref.read(bracketHighlightProvider.notifier).state = BracketHighlightState();
  }

  // CORRECTED: Update signature to use `Ref`
  @override
  void deactivateTab(EditorTab tab, Ref ref) {
    if (tab is! CodeEditorTab) return;
    ref.read(markProvider.notifier).state = null;
    ref.read(bracketHighlightProvider.notifier).state = BracketHighlightState();
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final codeTab = tab as CodeEditorTab;
    // Settings are watched inside CodeEditorMachine now
    // final settings = ref.watch(settingsProvider.select(...));

    return CodeEditorMachine(
      key: ValueKey(codeTab.file.uri),
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
    final currentTab = ProviderScope.containerOf(context).read(appNotifierProvider).value?.currentProject?.session.currentTab as CodeEditorTab?;
    if (currentTab == null) return textSpan;
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
    void processSpan(TextSpan span) {
      final text = span.text ?? '';
      final spanStyle = span.style ?? style;
      List<int> highlightIndices = [];

      for (var i = 0; i < text.length; i++) {
        if (highlightPositions.contains(currentPosition + i)) {
          highlightIndices.add(i);
        }
      }

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

      if (lastSplit < text.length) {
        spans.add(TextSpan(text: text.substring(lastSplit), style: spanStyle));
      }

      currentPosition += text.length;

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
    _createCommand(
      id: 'save',
      label: 'Save',
      icon: Icons.save,
      defaultPosition: CommandPosition.appBar,
      execute: (ref, _) async => ref.read(appNotifierProvider.notifier).saveCurrentTab(),
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

  CodeLineEditingController? _getController(WidgetRef ref) {
    final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    return tab is CodeEditorTab ? tab.controller : null;
  }
  
  // CORRECTED: Helper to get the full tab object
  CodeEditorTab? _getTab(WidgetRef ref) {
    final tab = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab));
    return tab is CodeEditorTab ? tab : null;
  }

  Future<void> _toggleComments(WidgetRef ref, CodeLineEditingController? ctrl) async {
    if (ctrl == null) return;
    final tab = _getTab(ref)!;
    final formatted = tab.commentFormatter.format(
      ctrl.value,
      ctrl.options.indent,
      true,
    );
    ctrl.runRevocableOp(() => ctrl.value = formatted);
  }

  Future<void> _reformatDocument(WidgetRef ref, CodeLineEditingController? ctrl) async {
    if (ctrl == null) return;
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

  Future<void> _selectBetweenBrackets(WidgetRef ref, CodeLineEditingController? ctrl) async {
    if (ctrl == null) return;
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

      for (int offset = 0; offset <= 1; offset++) {
        final index = position.offset - offset;
        if (index >= 0 && index < controller.codeLines[position.index].text.length) {
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
      print('Selection failed: ${e.toString()}');
    }
  }

  CodeLinePosition? _findMatchingBracket(CodeLines codeLines, CodeLinePosition position, Map<String, String> brackets) {
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

  Future<void> _extendSelection(WidgetRef ref, CodeLineEditingController? ctrl) async {
    if (ctrl == null) return;
    final controller = ctrl;
    final selection = controller.selection;

    final newBaseOffset = 0;
    final baseLineLength = controller.codeLines[selection.baseIndex].text.length;
    final extentLineLength = controller.codeLines[selection.extentIndex].text.length;
    final newExtentOffset = extentLineLength;

    controller.selection = CodeLineSelection(
      baseIndex: selection.baseIndex,
      baseOffset: newBaseOffset,
      extentIndex: selection.extentIndex,
      extentOffset: newExtentOffset,
    );
  }

  Future<void> _setMarkPosition(WidgetRef ref, CodeLineEditingController? ctrl) async {
    if (ctrl == null) return;
    ref.read(markProvider.notifier).state = ctrl.selection.base;
  }

  Future<void> _selectToMark(WidgetRef ref, CodeLineEditingController? ctrl) async {
    if (ctrl == null) return;
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
      final sessionNotifier = ref.read(sessionProvider.notifier);
      final currentTabIndex = ref.read(sessionProvider).currentTabIndex;
      sessionNotifier.updateTabLanguageKey(currentTabIndex, selectedLanguageKey);
    }
  }
}

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeLineEditingController controller;
  final CodeCommentFormatter? commentFormatter;
  final CodeIndicatorBuilder? indicatorBuilder;

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
    ref.read(appNotifierProvider.notifier).markCurrentTabDirty();
    _updateAllStatesFromController();
  }

  void _addControllerListeners(CodeLineEditingController controller) {
    controller.addListener(_handleControllerChange);
  }

  void _removeControllerListeners(CodeLineEditingController controller) {
    controller.removeListener(this._handleControllerChange);
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
    final codeEditorSettings = ref.watch(
      settingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    );

        // CORRECTED: Get language key from AppNotifier state
        final currentLanguageKey = ref.watch(appNotifierProvider.select(
          (s) {
            final tab = s.value?.currentProject?.session.currentTab;
            return (tab is CodeEditorTab) ? tab.languageKey : null;
          },
        ));

    // Get the selected theme name from settings
    final selectedThemeName = codeEditorSettings?.themeName ?? 'Atom One Dark'; // Default theme

    return Focus(
      autofocus: false,
      canRequestFocus: true,
      onFocusChange: (bool focus) => _handleFocusChange(),
      onKey: (n, e) => _handleKeyEvent(n, e),
      child: CodeEditor(
        controller: widget.controller,
        commentFormatter: widget.commentFormatter,
        indicatorBuilder: widget.indicatorBuilder,
        style: CodeEditorStyle(
          fontSize: codeEditorSettings?.fontSize ?? 12,
          fontFamily: codeEditorSettings?.fontFamily ?? 'JetBrainsMono',
          codeTheme: CodeHighlightTheme(
            // Retrieve the theme map using the selectedThemeName
            theme: CodeThemes.availableCodeThemes[selectedThemeName] ?? CodeThemes.availableCodeThemes['Atom One Dark']!,
            languages: CodeThemes.getHighlightThemeMode(currentLanguageKey),
          ),
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
  BracketHighlightState({this.bracketPositions = const {}, this.matchingBracketPosition, this.highlightedLines = const {}});
}

class BracketHighlightNotifier extends Notifier<BracketHighlightState> {
  @override
  BracketHighlightState build() { return BracketHighlightState(); }
  void handleBracketHighlight() {
  final currentTab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
      if (currentTab is! CodeEditorTab) {
          state = BracketHighlightState();
          return;
      }    final controller = currentTab.controller;
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

    state = BracketHighlightState(
      bracketPositions: newPositions,
      matchingBracketPosition: matchPosition,
      highlightedLines: newHighlightedLines,
    );
  }

  CodeLinePosition? _findMatchingBracket(CodeLines codeLines, CodeLinePosition position, Map<String, String> brackets) {
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
      onTap: () {},
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
  String themeName; // NEW: Added theme name

  CodeEditorSettings({
    this.wordWrap = false,
    this.fontSize = 14,
    this.fontFamily = 'JetBrainsMono',
    this.themeName = 'Atom One Dark', // NEW: Default theme
  });

  @override
  Map<String, dynamic> toJson() => {
    'wordWrap': wordWrap,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'themeName': themeName, // NEW: Serialize themeName
  };

  @override
  void fromJson(Map<String, dynamic> json) {
    wordWrap = json['wordWrap'] ?? false;
    fontSize = json['fontSize']?.toDouble() ?? 14;
    fontFamily = json['fontFamily'] ?? 'JetBrainsMono';
    themeName = json['themeName'] ?? 'Atom One Dark'; // NEW: Deserialize themeName
  }

  CodeEditorSettings copyWith({
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
    String? themeName, // NEW: copyWith themeName
  }) {
    return CodeEditorSettings(
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      themeName: themeName ?? this.themeName, // NEW: copyWith themeName
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
            DropdownMenuItem(value: 'RobotoMono', child: Text('Roboto Mono')),
          ],
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(fontFamily: value)),
        ),
        // NEW: Theme selection dropdown
        DropdownButtonFormField<String>(
          value: _currentSettings.themeName,
          decoration: const InputDecoration(labelText: 'Editor Theme'),
          items: CodeThemes.availableCodeThemes.keys.map((themeName) {
            return DropdownMenuItem(
              value: themeName,
              child: Text(themeName),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              _updateSettings(_currentSettings.copyWith(themeName: value));
            }
          },
        ),
      ],
    );
  }

  void _updateSettings(CodeEditorSettings newSettings) {
    setState(() => _currentSettings = newSettings);
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }
}