// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_editor_widgets.dart
// =========================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../../app/app_notifier.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../editor/services/editor_service.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/toast.dart';
import '../../editor_tab_models.dart';
import '../../tab_state_manager.dart';
import 'logic/code_editor_logic.dart';
import 'code_editor_models.dart';
import 'widgets/code_find_panel_view.dart';
import '../../../utils/code_themes.dart';
import 'code_editor_plugin.dart';
import 'widgets/goto_line_dialog.dart';

import '../../../editor/plugins/editor_command_context.dart';
import '../../../editor/services/text_editing_capability.dart';
import '../../../command/command_widgets.dart';

import 'code_editor_hot_state_dto.dart';
import 'widgets/code_editor_ui.dart';
import 'logic/code_editor_types.dart';
import 'logic/code_editor_utils.dart';

class CodeEditorMachine extends EditorWidget {
  @override
  final CodeEditorTab tab;

  const CodeEditorMachine({
    required GlobalKey<CodeEditorMachineState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  CodeEditorMachineState createState() => CodeEditorMachineState();
}

class CodeEditorMachineState extends EditorWidgetState<CodeEditorMachine>
    with TextEditable {
  late final CodeLineEditingController controller;
  late final FocusNode _focusNode;
  late final CodeFindController findController;
  CodeChunkController? _chunkController;
  CodeLinePosition? _markPosition;

  late final ValueNotifier<BracketHighlightState> _bracketHighlightNotifier;

  late CodeCommentFormatter _commentFormatter;
  late String? _languageKey;

  late CodeEditorStyle _style;

  late String? _baseContentHash;

  // --- TextEditable Interface Implementation ---

  @override
  Future<TextSelectionDetails> getSelectionDetails() async {
    final CodeLineSelection currentSelection = controller.selection;

    TextRange? textRange;
    if (!currentSelection.isCollapsed) {
      // Convert CodeLineSelection to TextRange
      textRange = TextRange(
        start: TextPosition(
          line: currentSelection.start.index,
          column: currentSelection.start.offset,
        ),
        end: TextPosition(
          line: currentSelection.end.index,
          column: currentSelection.end.offset,
        ),
      );
    }

    return TextSelectionDetails(
      range: textRange,
      content: controller.selectedText,
    );
  }

  @override
  void replaceSelection(String replacement, {TextRange? range}) {
    if (!mounted) return;

    CodeLineSelection? selectionToReplace;

    // This is the translation layer. If our abstract range is provided,
    // convert it to the concrete type the controller understands.
    if (range != null) {
      selectionToReplace = CodeLineSelection(
        baseIndex: range.start.line,
        baseOffset: range.start.column,
        extentIndex: range.end.line,
        extentOffset: range.end.column,
      );
    }

    // The controller's replaceSelection method handles the null case by
    // using the current selection, which is exactly what we want.
    controller.runRevocableOp(() {
      controller.replaceSelection(replacement, selectionToReplace);
    });
  }

  @override
  Future<bool> isSelectionCollapsed() async {
    return controller.selection.isCollapsed;
  }

  @override
  Future<String> getSelectedText() async {
    return controller.selectedText; // <-- The fix is here
  }

  @override
  void revealRange(TextRange range) {
    // 1. Convert our abstract TextPosition to the concrete re_editor CodeLine model.
    // Our TextPosition uses 1-based lines, which matches re_editor's CodeLine.
    final startPosition = CodeLinePosition(
      index: range.start.line, // re_editor CodeLinePosition is 0-based for line
      offset: range.start.column,
    );
    controller.selection = CodeLineSelection(
      baseIndex: range.start.line,
      baseOffset: range.start.column,
      extentIndex: range.end.line,
      extentOffset: range.end.column,
    );

    controller.makePositionCenterIfInvisible(startPosition);
  }

  @override
  Future<String> getTextContent() async {
    // Return the controller's current text, wrapped in a Future to match the interface.
    return controller.text;
  }

  @override
  void insertTextAtLine(int lineNumber, String textToInsert) {
    if (!mounted) return;

    // Clamp the line number to be within the valid range of the document.
    final line = lineNumber.clamp(0, controller.codeLines.length);

    // To insert at the beginning of a line, we replace a zero-length selection
    // at the start of that line.
    final selectionToReplace = CodeLineSelection.fromPosition(
      position: CodeLinePosition(index: line, offset: 0),
    );

    controller.runRevocableOp(() {
      controller.replaceSelection(textToInsert, selectionToReplace);
    });
  }

  @override
  void replaceAllOccurrences(String find, String replace) {
    if (!mounted) return;
    // This method is correct as the `replaceAll` method exists.
    controller.replaceAll(find, replace);
  }

  @override
  void replaceLines(int startLine, int endLine, String newContent) {
    if (!mounted) return;

    final start = startLine.clamp(0, controller.codeLines.length);
    // Clamp the end line to be a valid index.
    final end = endLine.clamp(0, controller.codeLines.length - 1);

    if (start > end) return;

    // Create a selection that spans the full lines to be replaced.
    // The selection's extent goes to the beginning (offset 0) of the line *after* the last line to replace.
    final selectionToReplace = CodeLineSelection(
      baseIndex: start,
      baseOffset: 0,
      extentIndex: (end + 1).clamp(0, controller.codeLines.length),
      extentOffset: 0,
    );

    // Perform the replacement within a single, undoable operation.
    controller.runRevocableOp(() {
      controller.replaceSelection(newContent, selectionToReplace);
    });
  }

  @override
  void replaceAllPattern(Pattern pattern, String replacement) {
    if (!mounted) return;
    controller.replaceAll(pattern, replacement);
  }

  @override
  void batchReplaceRanges(List<ReplaceRangeEdit> edits) {
    // Sort edits in reverse order of their starting position. This is crucial
    // to ensure that applying an edit does not shift the document offsets of
    // subsequent edits in the list.
    edits.sort((a, b) {
      final startA = a.range.start;
      final startB = b.range.start;
      if (startB.line != startA.line) {
        return startB.line.compareTo(startA.line);
      }
      return startB.column.compareTo(startA.column);
    });

    for (final edit in edits) {
      replaceSelection(edit.replacement, range: edit.range);
    }
  }

  @override
  void undo() {
    if (controller.canUndo) controller.undo();
  }

  @override
  void redo() {
    if (controller.canRedo) controller.redo();
  }

  @override
  Future<EditorContent> getContent() async {
    return EditorContentString(controller.text);
  }

  @override
  void onSaveSuccess(String newHash) {
    if (!mounted) return;
    setState(() {
      _baseContentHash = newHash;
    });
    controller.markCurrentStateAsClean();
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    return CodeEditorHotStateDto(
      content: controller.text,
      languageKey: _languageKey,
      baseContentHash: _baseContentHash,
    );
  }

  @override
  void init() {
    _focusNode = FocusNode();
    _baseContentHash = widget.tab.initialBaseContentHash;
    _bracketHighlightNotifier = ValueNotifier(const BracketHighlightState());

    final fileUri = ref.read(tabMetadataProvider)[widget.tab.id]?.file.uri;
    if (fileUri == null) {
      throw StateError("Could not find metadata for tab ID: ${widget.tab.id}");
    }

    _languageKey =
        widget.tab.initialLanguageKey ?? CodeThemes.inferLanguageKey(fileUri);
    _commentFormatter = CodeEditorLogic.getCommentFormatter(fileUri);

    controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(widget.tab.initialContent),
      spanBuilder: _buildHighlightingSpan,
    );
    findController = CodeFindController(controller);

    findController.addListener(syncCommandContext);
    controller.addListener(_onControllerChange);
    controller.dirty.addListener(_onDirtyStateChange);
  }

  @override
  void onFirstFrameReady() {
    if (mounted) {
      syncCommandContext();
      if (widget.tab.cachedContent != null) {
        controller.text = widget.tab.cachedContent!;
      }
      if (!widget.tab.onReady.isCompleted) {
        widget.tab.onReady.complete(this);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateStyleAndRecognizers();
  }

  @override
  void didUpdateWidget(covariant CodeEditorMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFileUri =
        ref.read(tabMetadataProvider)[oldWidget.tab.id]?.file.uri;
    final newFileUri = ref.read(tabMetadataProvider)[widget.tab.id]?.file.uri;

    if (newFileUri != null && newFileUri != oldFileUri) {
      setState(() {
        final newLanguageKey = CodeThemes.inferLanguageKey(newFileUri);
        if (newLanguageKey != _languageKey) {
          _languageKey = newLanguageKey;
          _updateStyleAndRecognizers(); // Rebuild style for new language
        }
        _commentFormatter = CodeEditorLogic.getCommentFormatter(newFileUri);
      });
    }
  }

  @override
  void dispose() {
    _bracketHighlightNotifier.dispose();
    findController.removeListener(syncCommandContext);
    controller.removeListener(syncCommandContext);
    controller.dirty.removeListener(_onDirtyStateChange);
    controller.dispose();
    _focusNode.dispose();
    findController.dispose();
    super.dispose();
  }

  void _updateStyleAndRecognizers() {
    final codeEditorSettings = ref.read(
      settingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    );

    final selectedThemeName = codeEditorSettings?.themeName ?? 'Atom One Dark';
    final bool enableLigatures = codeEditorSettings?.fontLigatures ?? true;
    final List<FontFeature>? fontFeatures = enableLigatures
        ? null
        : const [
            FontFeature.disable('liga'),
            FontFeature.disable('clig'),
            FontFeature.disable('calt'),
          ];

    _style = CodeEditorStyle(
      fontHeight: codeEditorSettings?.fontHeight,
      fontSize: codeEditorSettings?.fontSize ?? 12.0,
      fontFamily: codeEditorSettings?.fontFamily ?? 'JetBrainsMono',
      fontFeatures: fontFeatures,
      codeTheme: CodeHighlightTheme(
        theme: CodeThemes.availableCodeThemes[selectedThemeName] ??
            CodeThemes.availableCodeThemes['Atom One Dark']!,
        languages: CodeThemes.getHighlightThemeMode(_languageKey),
      ),
    );
  }

  Widget _buildSelectionAppBar() {
    return const CodeEditorSelectionAppBar();
  }

  // --- LOGIC AND METHODS ---

  Future<void> showGoToLineDialog() async {
    if (!mounted) return;
    final int maxLines = controller.codeLines.length;
    final int currentLine = controller.selection.start.index;
    final int? targetLineIndex = await showDialog<int>(
      context: context,
      builder:
          (ctx) => GoToLineDialog(maxLine: maxLines, currentLine: currentLine),
    );
    if (targetLineIndex != null) {
      final CodeLinePosition targetPosition =
          CodeLinePosition(index: targetLineIndex, offset: 0);
      controller.selection =
          CodeLineSelection.fromPosition(position: targetPosition);
      controller.makePositionCenterIfInvisible(targetPosition);
    }
  }

  void selectOrExpandLines() {
    final CodeLineSelection currentSelection = controller.selection;
    final List<CodeLine> lines = controller.codeLines.toList();
    final bool isAlreadyFullLineSelection = currentSelection.start.offset == 0 &&
        currentSelection.end.offset == 0 &&
        currentSelection.end.index > currentSelection.start.index;

    if (isAlreadyFullLineSelection) {
      if (currentSelection.end.index < lines.length) {
        controller.selection = currentSelection.copyWith(
            extentIndex: currentSelection.end.index + 1, extentOffset: 0);
      }
    } else {
      final newStartIndex = currentSelection.start.index;
      final newEndIndex =
          (currentSelection.end.index + 1).clamp(0, lines.length);
      controller.selection = CodeLineSelection(
          baseIndex: newStartIndex,
          baseOffset: 0,
          extentIndex: newEndIndex,
          extentOffset: 0);
    }
    _onControllerChange();
  }

  void selectCurrentChunk() {
    if (_chunkController == null) return;
    controller.selectChunk(_chunkController!.value);
    _onControllerChange();
  }

  void extendSelection() {
    final CodeLineSelection currentSelection = controller.selection;
    CodeLineSelection? newSelection;

    final enclosingBlock = CodeEditorUtils.findSmallestEnclosingBlock(
      currentSelection,
      controller,
    );

    if (enclosingBlock != null) {
      if (currentSelection == enclosingBlock.contents) {
        newSelection = enclosingBlock.full;
      } else {
        newSelection = enclosingBlock.contents;
      }
    }

    if (newSelection != null && newSelection != currentSelection) {
      controller.selection = newSelection;
      _onControllerChange();
    }
  }

  // --- NEW PUBLIC METHODS for Commands ---
  void showFindPanel() {
    findController.findMode();
  }

  void showReplacePanel() {
    findController.replaceMode();
  }

  void _onImportTap(String relativePath) async {
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final fileHandler = ref.read(projectRepositoryProvider)?.fileHandler;
    final currentFileMetadata = ref.read(tabMetadataProvider)[widget.tab.id];

    if (fileHandler == null || currentFileMetadata == null) return;

    try {
      final currentDirectoryUri =
          fileHandler.getParentUri(currentFileMetadata.file.uri);
      final pathSegments = [
        ...currentDirectoryUri.split('%2F'),
        ...relativePath.split('/')
      ];
      final resolvedSegments = <String>[];

      for (final segment in pathSegments) {
        if (segment == '..') {
          if (resolvedSegments.isNotEmpty) {
            resolvedSegments.removeLast();
          }
        } else if (segment != '.' && segment.isNotEmpty) {
          resolvedSegments.add(segment);
        }
      }

      final resolvedUri = resolvedSegments.join('%2F');
      final targetFile = await fileHandler.getFileMetadata(resolvedUri);

      if (targetFile != null) {
        await appNotifier.openFileInEditor(targetFile);
      } else {
        MachineToast.error('File not found: $relativePath');
      }
    } catch (e) {
      MachineToast.error('Could not open file: $e');
    }
  }

  void _onDirtyStateChange() {
    if (!mounted) return;
    final editorService = ref.read(editorServiceProvider);
    if (controller.dirty.value) {
      editorService.markCurrentTabDirty();
    } else {
      editorService.markCurrentTabClean();
    }
  }

  void _onControllerChange() {
    if (!mounted) return;

    _bracketHighlightNotifier.value =
        CodeEditorUtils.calculateBracketHighlights(controller);

    syncCommandContext();

    if (controller.dirty.value) {
      final project = ref.read(appNotifierProvider).value?.currentProject;
      if (project != null) {
        ref
            .read(editorServiceProvider)
            .updateAndCacheDirtyTab(project, widget.tab);
      }
    }
  }

  Map<String, dynamic> getHotState() {
    return {
      'content': controller.text,
      'languageKey': _languageKey,
      'baseContentHash': _baseContentHash,
    };
  }

  @override
  void syncCommandContext() {
    if (!mounted) return;

    final hasSelection = !controller.selection.isCollapsed;
    Widget? appBarOverride;
    Key? appBarOverrideKey;

    if (findController.value != null) {
      appBarOverride = CodeFindAppBar(controller: findController);
      appBarOverrideKey = ValueKey('findController_toolbar');
    } else if (hasSelection) {
      appBarOverride = _buildSelectionAppBar();
      appBarOverrideKey = const ValueKey('selection_toolbar_active');
    }

    final newContext = CodeEditorCommandContext(
      canUndo: controller.canUndo,
      canRedo: controller.canRedo,
      hasSelection: hasSelection,
      hasMark: _markPosition != null,
      appBarOverride: appBarOverride,
      appBarOverrideKey: appBarOverrideKey,
    );

    ref.read(commandContextProvider(widget.tab.id).notifier).state = newContext;
  }

  void setMark() {
    setState(() {
      _markPosition = controller.selection.base;
    });
    syncCommandContext();
  }

  void selectToMark() {
    if (_markPosition == null) return;
    final currentPosition = controller.selection.base;
    final start =
        CodeEditorUtils.comparePositions(_markPosition!, currentPosition) < 0
            ? _markPosition!
            : currentPosition;
    final end =
        CodeEditorUtils.comparePositions(_markPosition!, currentPosition) < 0
            ? currentPosition
            : _markPosition!;
    controller.selection = CodeLineSelection(
      baseIndex: start.index,
      baseOffset: start.offset,
      extentIndex: end.index,
      extentOffset: end.offset,
    );
  }

  void toggleComments() {
    final formatted = _commentFormatter.format(
      controller.value,
      controller.options.indent,
      true,
    );
    controller.runRevocableOp(() => controller.value = formatted);
  }

  Future<void> showLanguageSelectionDialog() async {
    final selectedLanguageKey = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Language'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: CodeThemes.languageNameToModeMap.keys.length,
            itemBuilder: (context, index) {
              final langKey =
                  CodeThemes.languageNameToModeMap.keys.elementAt(index);
              return ListTile(
                title: Text(CodeThemes.formatLanguageName(langKey)),
                onTap: () => Navigator.pop(ctx, langKey),
              );
            },
          ),
        ),
      ),
    );
    if (selectedLanguageKey != null && selectedLanguageKey != _languageKey) {
      setState(() {
        _languageKey = selectedLanguageKey;
      });
      _updateStyleAndRecognizers();
      ref.read(editorServiceProvider).markCurrentTabDirty();
    }
  }

  TextSpan _buildHighlightingSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    // This method now acts as a simple wrapper, collecting instance state
    // and passing it to the pure utility function for processing.
    return CodeEditorUtils.buildHighlightingSpan(
      context: context,
      index: index,
      codeLine: codeLine,
      textSpan: textSpan,
      style: style,
      bracketHighlightState: _bracketHighlightNotifier.value,
      onImportTap: _onImportTap,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_focusNode.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final arrowKeyDirections = {
      LogicalKeyboardKey.arrowUp: AxisDirection.up,
      LogicalKeyboardKey.arrowDown: AxisDirection.down,
      LogicalKeyboardKey.arrowLeft: AxisDirection.left,
      LogicalKeyboardKey.arrowRight: AxisDirection.right,
    };
    final direction = arrowKeyDirections[event.logicalKey];
    final shiftPressed = HardwareKeyboard.instance.isShiftPressed;

    if (direction != null) {
      if (shiftPressed) {
        controller.extendSelection(direction);
      } else {
        controller.moveCursor(direction);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tabMetadataProvider.select((m) => m[widget.tab.id]?.file.uri),
        (previous, next) {
      if (previous != next && next != null) {
        setState(() {
          final newLanguageKey = CodeThemes.inferLanguageKey(next);
          if (newLanguageKey != _languageKey) {
            _languageKey = newLanguageKey;
            _updateStyleAndRecognizers();
          }
          _commentFormatter = CodeEditorLogic.getCommentFormatter(next);
        });
      }
    });

    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: CodeEditor(
        controller: controller,
        focusNode: _focusNode,
        findController: findController,
        findBuilder: (context, controller, readOnly) {
          return CodeFindPanelView(
            controller: controller,
            iconSelectedColor: colorScheme.primary,
            iconColor: colorScheme.onSurface.withValues(alpha: 0.6),
            readOnly: readOnly,
          );
        },
        commentFormatter: _commentFormatter,
        verticalScrollbarWidth: 16.0,
        scrollbarBuilder: (context, child, details) {
          return GrabbableScrollbar(
            details: details,
            thickness: 16.0,
            child: child,
          );
        },
        indicatorBuilder:
            (context, editingController, chunkController, notifier) {
          _chunkController = chunkController;
          return CustomEditorIndicator(
            controller: editingController,
            chunkController: chunkController,
            notifier: notifier,
            bracketHighlightNotifier: _bracketHighlightNotifier,
          );
        },
        sperator: Container(
          width: 2,
          color: colorScheme.surfaceContainerHighest,
        ),
        style: _style,
        wordWrap: ref.watch(
          settingsProvider.select(
            (s) =>
                (s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?)
                    ?.wordWrap ??
                false,
          ),
        ),
      ),
    );
  }
}