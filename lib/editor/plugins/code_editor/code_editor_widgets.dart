import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:re_editor/re_editor.dart';
import 'package:flex_color_picker/flex_color_picker.dart';

import '../../../app/app_notifier.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../../editor/services/editor_service.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/toast.dart';
import '../../models/editor_tab_models.dart';
import '../../tab_metadata_notifier.dart';
import 'logic/code_editor_logic.dart';
import 'code_editor_models.dart';
import 'widgets/code_find_panel_view.dart';
import '../../../utils/code_themes.dart';
import 'widgets/goto_line_dialog.dart';
import '../../models/editor_command_context.dart';
import '../../models/text_editing_capability.dart';
import 'package:machine/editor/services/language/language_models.dart';
import 'package:machine/editor/services/language/language_registry.dart';
import 'code_editor_hot_state_dto.dart';
import 'widgets/code_editor_ui.dart';
import 'logic/code_editor_types.dart';
import 'logic/code_editor_utils.dart';
import '../../../project/project_settings_notifier.dart';

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

  late LanguageConfig _languageConfig;
  late CodeCommentFormatter _commentFormatter;
  
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
      languageId: _languageConfig.id,
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

    if (widget.tab.initialLanguageId != null) {
      _languageConfig = Languages.getById(widget.tab.initialLanguageId!);
    } else {
      _languageConfig = Languages.getForFile(fileUri);
    }
        
    _updateCommentFormatter();


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
    _updateCommentFormatter();
  }

  @override
  void didUpdateWidget(covariant CodeEditorMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFileUri = ref.read(tabMetadataProvider)[oldWidget.tab.id]?.file.uri;
    final newFileUri = ref.read(tabMetadataProvider)[widget.tab.id]?.file.uri;

    if (newFileUri != null && newFileUri != oldFileUri) {
      setState(() {
        // Reload config on file rename/change
        _languageConfig = Languages.getForFile(newFileUri);
        _updateStyleAndRecognizers();
        _updateCommentFormatter();
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
      effectiveSettingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    );

    final selectedThemeName = codeEditorSettings?.themeName ?? 'Atom One Dark';
    final bool enableLigatures = codeEditorSettings?.fontLigatures ?? true;
    final List<FontFeature>? fontFeatures =
        enableLigatures
            ? null
            : const [
              FontFeature.disable('liga'),
              FontFeature.disable('clig'),
              FontFeature.disable('calt'),
            ];

    final Map<String, CodeHighlightThemeMode> languageMap = {};
    if (_languageConfig.highlightMode != null) {
      languageMap[_languageConfig.id] = CodeHighlightThemeMode(
        mode: _languageConfig.highlightMode!
      );
    }

    _style = CodeEditorStyle(
      fontHeight: codeEditorSettings?.fontHeight,
      fontSize: codeEditorSettings?.fontSize ?? 12.0,
      fontFamily: codeEditorSettings?.fontFamily ?? 'JetBrainsMono',
      fontFeatures: fontFeatures,
      codeTheme: CodeHighlightTheme(
        theme: CodeThemes.availableCodeThemes[selectedThemeName] ??
            CodeThemes.availableCodeThemes['Atom One Dark']!,
        languages: languageMap,
      ),
    );
  }
  
  void _updateCommentFormatter() {
    if (_languageConfig.comments != null) {
      _commentFormatter = DefaultCodeCommentFormatter(
        singleLinePrefix: _languageConfig.comments!.singleLine,
        multiLinePrefix: _languageConfig.comments!.blockBegin,
        multiLineSuffix: _languageConfig.comments!.blockEnd,
      );
    } else {
      _commentFormatter = DefaultCodeCommentFormatter(singleLinePrefix: '');
    }
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
      final CodeLinePosition targetPosition = CodeLinePosition(
        index: targetLineIndex,
        offset: 0,
      );
      controller.selection = CodeLineSelection.fromPosition(
        position: targetPosition,
      );
      controller.makePositionCenterIfInvisible(targetPosition);
    }
  }

void selectOrExpandLines() {
  final CodeLineSelection currentSelection = controller.selection;
  final List<CodeLine> lines = controller.codeLines.toList();
  final bool isAlreadyFullLineSelection =
      currentSelection.start.offset == 0 &&
      currentSelection.end.offset == 0 &&
      currentSelection.end.index > currentSelection.start.index;

  if (isAlreadyFullLineSelection) {
    // For expanding selection, we can only expand if there's a next line
    if (currentSelection.end.index < lines.length - 1) {
      controller.selection = currentSelection.copyWith(
        extentIndex: currentSelection.end.index + 1,
        extentOffset: 0,
      );
    } else if (currentSelection.end.index == lines.length - 1) {
      controller.selection = currentSelection.copyWith(
        extentIndex: lines.length - 1, // Stay on last line
        extentOffset: lines.last.length, // Set to end of the last line
      );
    }
  } else {
    final newStartIndex = currentSelection.start.index;
    
    // Special case: if we're on the last line, select just this line
    if (currentSelection.end.index == lines.length - 1) {
      controller.selection = CodeLineSelection(
        baseIndex: newStartIndex,
        baseOffset: 0,
        extentIndex: lines.length - 1, // Stay on last line
        extentOffset: lines.last.length, // Set to end of the last line
      );
    } else {
      // Normal case: select from current line to next line
      final newEndIndex = currentSelection.end.index + 1;
      controller.selection = CodeLineSelection(
        baseIndex: newStartIndex,
        baseOffset: 0,
        extentIndex: newEndIndex,
        extentOffset: 0,
      );
    }
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
  
  void adjustSelectionIfNeeded() {
    final CodeLineSelection currentSelection = controller.selection;
    final List<CodeLine> lines = controller.codeLines.toList();
    
    // Check if we have a multiline selection that ends at offset 0
    final bool isMultilineWithZeroEnd = 
        currentSelection.end.index > currentSelection.start.index &&
        currentSelection.end.offset == 0;
    
    if (isMultilineWithZeroEnd) {
      // Move selection end to the previous line, at the end of that line
      final previousLineIndex = currentSelection.end.index - 1;
      if (previousLineIndex >= 0) {
        final previousLine = lines[previousLineIndex];
        controller.selection = currentSelection.copyWith(
          extentIndex: previousLineIndex,
          extentOffset: previousLine.length,
        );
        _onControllerChange();
      }
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
      final currentDirectoryUri = fileHandler.getParentUri(
        currentFileMetadata.file.uri,
      );
      final pathSegments = [
        ...currentDirectoryUri.split('%2F'),
        ...relativePath.split('/'),
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
  
  Future<void> _onColorCodeTap(int lineIndex, ColorMatch match) async {
    if (!mounted) return;

    Color pickerColor = match.color;

    final result = await showDialog<Color>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              color: pickerColor,
              onColorChanged: (Color color) => pickerColor = color,
              width: 40,
              height: 40,
              spacing: 5,
              runSpacing: 5,
              borderRadius: 4,
              wheelDiameter: 165,
              enableOpacity: true,
              showColorCode: true,
              colorCodeHasColor: true,
              pickersEnabled: const <ColorPickerType, bool>{
                ColorPickerType.both: false,
                ColorPickerType.primary: true,
                ColorPickerType.accent: true,
                ColorPickerType.bw: false,
                ColorPickerType.custom: true,
                ColorPickerType.wheel: true,
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            FilledButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(pickerColor),
            ),
          ],
        );
      },
    );

    if (result != null && result != match.color) {
      // --- FIX START: Smarter replacement based on original format ---
      String newColorString;
      final String originalText = match.text;

      if (originalText.startsWith('#')) {
        // Respect original length to preserve alpha/no-alpha format
        if (originalText.length == 7 || originalText.length == 4) { // #RRGGBB or #RGB
            newColorString = '#${(result.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
        } else { // #AARRGGBB or #RGBA
            newColorString = '#${result.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
        }
      } else if (originalText.startsWith('Color.fromARGB')) {
          newColorString = 'Color.fromARGB(${result.alpha}, ${result.red}, ${result.green}, ${result.blue})';
      } else if (originalText.startsWith('Color.fromRGBO')) {
          // Convert alpha to opacity. Format to avoid excessive decimals.
          String opacity = (result.alpha / 255.0).toStringAsPrecision(2);
          if (opacity.endsWith('.0')) opacity = opacity.substring(0, opacity.length - 2);
          newColorString = 'Color.fromRGBO(${result.red}, ${result.green}, ${result.blue}, $opacity)';
      } else if (originalText.startsWith('Color(')) {
          // Canonical Dart format with an ARGB hex value.
          newColorString = 'Color(0x${result.value.toRadixString(16).toUpperCase()})';
      } else {
          // Fallback, should not be reached.
          newColorString = '#${result.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
      }
      // --- FIX END ---

      final rangeToReplace = TextRange(
        start: TextPosition(line: lineIndex, column: match.start),
        end: TextPosition(line: lineIndex, column: match.end),
      );

      replaceSelection(newColorString, range: rangeToReplace);
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

    _bracketHighlightNotifier
        .value = CodeEditorUtils.calculateBracketHighlights(controller);

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
      'languageId': _languageConfig.id,
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
    adjustSelectionIfNeeded();
    final formatted = _commentFormatter.format(
      controller.value,
      controller.options.indent,
      true,
    );
    controller.runRevocableOp(() => controller.value = formatted);
  }
  
  void deleteCommentText() {
    adjustSelectionIfNeeded();
    final selection = controller.selection;
    final singleLinePrefix = _languageConfig.comments?.singleLine;

    // Can't do anything if we don't know the single-line comment syntax.
    if (singleLinePrefix == null || singleLinePrefix.isEmpty) {
      return;
    }

    final startLine = selection.start.index;
    final endLine = selection.end.index;

    // 1. Build a list of the new line contents.
    final List<String> newLines = [];
    for (int i = startLine; i <= endLine; i++) {
      final line = controller.codeLines[i].text;
      final commentIndex = line.indexOf(singleLinePrefix);

      if (commentIndex != -1) {
        // A comment is found.
        final contentBeforeComment = line.substring(0, commentIndex);
        if (contentBeforeComment.trim().isNotEmpty) {
          // If there's non-whitespace content before the comment, keep it.
          // This removes the comment prefix and the comment text.
          newLines.add(contentBeforeComment.trimRight());
        }
        // Otherwise, it's a comment-only line, which we delete by not adding
        // it to the list of new lines.
      } else {
        // No comment, keep the line as is.
        newLines.add(line.trimRight());
      }
    }

    // 2. Define a selection that covers the full lines we are replacing.
    final selectionToReplace = CodeLineSelection(
      baseIndex: startLine,
      baseOffset: 0, // from the beginning of the first line
      extentIndex: endLine,
      extentOffset: controller.codeLines[endLine].length, // to the end of the last line
    );

    // 3. Perform the replacement in a single, undoable operation.
    controller.runRevocableOp(() {
      controller.replaceSelection(newLines.join('\n'), selectionToReplace);
    });
  }

  Future<void> showLanguageSelectionDialog() async {
    final allLanguages = Languages.all; // Use the public list from registry
    
    final selectedLanguageId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Language'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allLanguages.length,
            itemBuilder: (context, index) {
              final lang = allLanguages[index];
              return ListTile(
                title: Text(lang.name),
                // Highlight current selection
                selected: lang.id == _languageConfig.id,
                onTap: () => Navigator.pop(ctx, lang.id),
              );
            },
          ),
        ),
      ),
    );

    if (selectedLanguageId != null && selectedLanguageId != _languageConfig.id) {
      setState(() {
        // Update config by looking up the new ID
        _languageConfig = Languages.getById(selectedLanguageId);
        _updateStyleAndRecognizers();
        _updateCommentFormatter();
      });
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
      onColorCodeTap: _onColorCodeTap,
      languageConfig: _languageConfig,
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
    ref.listen(tabMetadataProvider.select((m) => m[widget.tab.id]?.file.uri), (
      previous,
      next,
    ) {
      if (previous != next && next != null) {
        setState(() {
          final newLanguageConfig = Languages.getForFile(next);
          if (newLanguageConfig.id != _languageConfig.id) {
            _languageConfig = newLanguageConfig;
            _updateStyleAndRecognizers();
          }
          _updateCommentFormatter();
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
        indicatorBuilder: (
          context,
          editingController,
          chunkController,
          notifier,
        ) {
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
          effectiveSettingsProvider.select(
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