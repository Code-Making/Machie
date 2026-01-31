import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:re_editor/re_editor.dart';

import '../../../app/app_notifier.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../../editor/services/editor_service.dart';
import '../../../project/project_settings_notifier.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/code_themes.dart';
import '../../../utils/toast.dart';
import '../../models/editor_command_context.dart';
import '../../models/editor_tab_models.dart';
import '../../models/text_editing_capability.dart';
import '../../services/language/language_models.dart';
import '../../services/language/language_registry.dart';
import '../../tab_metadata_notifier.dart';
import 'code_editor_hot_state_dto.dart';
import 'code_editor_models.dart';
import 'logic/code_editor_types.dart';
import 'logic/code_editor_utils.dart';
import 'widgets/code_editor_ui.dart';
import 'widgets/code_find_panel_view.dart';
import 'widgets/goto_line_dialog.dart';

class CodeEditorMachine extends EditorWidget {
  @override
  // ignore: overridden_fields
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


  late SpanParser _cachedParser;
  bool _enableBracketMatching = true;
  bool _enableColorPreviews = true;
  bool _enableLinks = true;

  late String? _baseContentHash;

  late final LineResourceManager _resourceManager; 


  @override
  Future<TextSelectionDetails> getSelectionDetails() async {
    final CodeLineSelection currentSelection = controller.selection;

    TextRange? textRange;
    if (!currentSelection.isCollapsed) {
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

    if (range != null) {
      selectionToReplace = CodeLineSelection(
        baseIndex: range.start.line,
        baseOffset: range.start.column,
        extentIndex: range.end.line,
        extentOffset: range.end.column,
      );
    }

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
    final startPosition = CodeLinePosition(
      index: range.start.line,
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
    return controller.text;
  }

  @override
  void insertTextAtLine(int lineNumber, String textToInsert) {
    if (!mounted) return;

    final line = lineNumber.clamp(0, controller.codeLines.length);

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
    controller.replaceAll(find, replace);
  }

  @override
  void replaceLines(int startLine, int endLine, String newContent) {
    if (!mounted) return;

    final start = startLine.clamp(0, controller.codeLines.length);
    final end = endLine.clamp(0, controller.codeLines.length - 1);

    if (start > end) return;

    final selectionToReplace = CodeLineSelection(
      baseIndex: start,
      baseOffset: 0,
      extentIndex: (end + 1).clamp(0, controller.codeLines.length),
      extentOffset: 0,
    );

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
    _resourceManager = LineResourceManager();
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

    _updateInternalConfig();

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
    setState(() {
      _updateInternalConfig();
    });
  }

  @override
  void didUpdateWidget(covariant CodeEditorMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFileUri =
        ref.read(tabMetadataProvider)[oldWidget.tab.id]?.file.uri;
    final newFileUri = ref.read(tabMetadataProvider)[widget.tab.id]?.file.uri;

    if (newFileUri != null && newFileUri != oldFileUri) {
      setState(() {
        _languageConfig = Languages.getForFile(newFileUri);
        _updateInternalConfig();
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
    _resourceManager.disposeAll(); 
    super.dispose();
  }

  void _updateInternalConfig() {
    _commentFormatter = _getCommentFormatter();
    _cachedParser = _languageConfig.parser;

    final settings =
        ref.read(
          effectiveSettingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
          ),
        ) ??
        CodeEditorSettings();

    _enableBracketMatching = settings.enableBracketMatching;
    _enableColorPreviews = settings.enableColorPreviews;
    _enableLinks = settings.enableLinks;

    final selectedThemeName = settings.themeName;
    final bool enableLigatures = settings.fontLigatures;

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
        mode: _languageConfig.highlightMode!,
      );
    }

    _style = CodeEditorStyle(
      fontHeight: settings.fontHeight,
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      fontFeatures: fontFeatures,
      codeTheme: CodeHighlightTheme(
        theme:
            CodeThemes.availableCodeThemes[selectedThemeName] ??
            CodeThemes.availableCodeThemes['Atom One Dark']!,
        languages: languageMap,
      ),
    );
  }

  CodeCommentFormatter _getCommentFormatter() {
    if (_languageConfig.comments != null) {
      return DefaultCodeCommentFormatter(
        singleLinePrefix: _languageConfig.comments!.singleLine,
        multiLinePrefix: _languageConfig.comments!.blockBegin,
        multiLineSuffix: _languageConfig.comments!.blockEnd,
      );
    }
    return DefaultCodeCommentFormatter(singleLinePrefix: '');
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
      if (currentSelection.end.index < lines.length - 1) {
        controller.selection = currentSelection.copyWith(
          extentIndex: currentSelection.end.index + 1,
          extentOffset: 0,
        );
      } else if (currentSelection.end.index == lines.length - 1) {
        controller.selection = currentSelection.copyWith(
          extentIndex: lines.length - 1,
          extentOffset: lines.last.length,
        );
      }
    } else {
      final newStartIndex = currentSelection.start.index;

      if (currentSelection.end.index == lines.length - 1) {
        controller.selection = CodeLineSelection(
          baseIndex: newStartIndex,
          baseOffset: 0,
          extentIndex: lines.length - 1,
          extentOffset: lines.last.length,
        );
      } else {
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

    final bool isMultilineWithZeroEnd =
        currentSelection.end.index > currentSelection.start.index &&
        currentSelection.end.offset == 0;

    if (isMultilineWithZeroEnd) {
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


  void showFindPanel() {
    findController.findMode();
  }

  void showReplacePanel() {
    findController.replaceMode();
  }

  /// Parses the target for line numbers (e.g., "file.dart:10:5") and navigates.
  void _onLinkTap(LinkSpan span) async {
    final target = span.target.trim();
    if (target.isEmpty) return;

    if (target.startsWith('http://') || target.startsWith('https://')) {
      MachineToast.info('Opening URL: $target');
      return;
    }

    final parsed = _parseFileTarget(target);
    if (parsed == null) {
      MachineToast.error('Invalid link format: $target');
      return;
    }

    final appNotifier = ref.read(appNotifierProvider.notifier);
    final repo = ref.read(projectRepositoryProvider);
    final currentFileMetadata = ref.read(tabMetadataProvider)[widget.tab.id];

    if (repo == null || currentFileMetadata == null) return;


    final bool hasLineNumber = parsed.line != null;
    final bool isRelativeImport = parsed.path.startsWith('.');

    final bool resolveFromContext = isRelativeImport && !hasLineNumber;

    String cleanPath = parsed.path;
    /*
    if (isPackageScheme) {
    }
    */

    try {
      final String baseUri =
          resolveFromContext
              ? repo.fileHandler.getParentUri(
                currentFileMetadata.file.uri,
              )
              : repo.rootUri;

      final candidates =
          _languageConfig.importResolver?.call(cleanPath) ?? [cleanPath];

      ProjectDocumentFile? targetFile;

      for (final candidate in candidates) {
        final result = await repo.fileHandler.resolvePath(baseUri, candidate);

        if (result != null) {
          if (!result.isDirectory) {
            targetFile = result;
            break;
          }
        }
      }

      if (targetFile != null) {
        final onReady = Completer<EditorWidgetState>();

        final didOpen = await appNotifier.openFileInEditor(
          targetFile,
          onReadyCompleter: onReady,
        );

        if (didOpen) {
          if (parsed.line != null) {
            final editorState = await onReady.future;
            if (editorState is TextEditable) {
              final lineIndex = parsed.line! - 1;
              final colIndex = (parsed.column ?? 1) - 1;

              (editorState as TextEditable).revealRange(
                TextRange(
                  start: TextPosition(line: lineIndex, column: colIndex),
                  end: TextPosition(line: lineIndex, column: colIndex),
                ),
              );
            }
          }
        }
      } else {
        MachineToast.error('File not found: $cleanPath');
      }
    } catch (e) {
      MachineToast.error('Could not open file: $e');
    }
  }

  /// Helper to extract path, line, and column from strings like:
  /// - "/lib/main.dart:10:5"
  /// - "package:foo/bar.dart"
  /// - "../utils.dart"
  ({String path, int? line, int? column})? _parseFileTarget(String target) {
    // Regex for: path + optional(:line) + optional(:col)
    // We look for :digit at the end of the string.
    final match = RegExp(r'^(.*?)(?::(\d+))?(?::(\d+))?$').firstMatch(target);

    if (match == null) return null;

    final path = match.group(1);
    if (path == null || path.isEmpty) return null;

    final line = match.group(2) != null ? int.parse(match.group(2)!) : null;
    final col = match.group(3) != null ? int.parse(match.group(3)!) : null;

    return (path: path, line: line, column: col);
  }

  void _onColorCodeTap(int lineIndex, ColorSpan span) async {
    if (!mounted) return;

    Color pickerColor = span.color;

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

    if (result != null && result != span.color) {
      String newColorString;
      final String originalText = span.originalText;

      // Smart format replacement
      if (originalText.startsWith('#')) {
        if (originalText.length == 7 || originalText.length == 4) {
          newColorString =
              '#${(result.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
        } else {
          newColorString =
              '#${result.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
        }
      } else if (originalText.startsWith('Color.fromARGB')) {
        newColorString =
            'Color.fromARGB(${result.a}, ${result.r}, ${result.g}, ${result.b})';
      } else if (originalText.startsWith('Color.fromRGBO')) {
        String opacity = (result.a / 255.0).toStringAsPrecision(2);
        if (opacity.endsWith('.0'))
          opacity = opacity.substring(0, opacity.length - 2);
        newColorString =
            'Color.fromRGBO(${result.r}, ${result.g}, ${result.b}, $opacity)';
      } else if (originalText.startsWith('Color(')) {
        newColorString =
            'Color(0x${result.toARGB32().toRadixString(16).toUpperCase()})';
      } else {
        newColorString =
            '#${result.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
      }

      final rangeToReplace = TextRange(
        start: TextPosition(line: lineIndex, column: span.start),
        end: TextPosition(line: lineIndex, column: span.end),
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

    if (singleLinePrefix == null || singleLinePrefix.isEmpty) {
      return;
    }

    final startLine = selection.start.index;
    final endLine = selection.end.index;

    final List<String> newLines = [];
    for (int i = startLine; i <= endLine; i++) {
      final line = controller.codeLines[i].text;
      final commentIndex = line.indexOf(singleLinePrefix);

      if (commentIndex != -1) {
        final contentBeforeComment = line.substring(0, commentIndex);
        if (contentBeforeComment.trim().isNotEmpty) {
          newLines.add(contentBeforeComment.trimRight());
        }
      } else {
        newLines.add(line.trimRight());
      }
    }

    final selectionToReplace = CodeLineSelection(
      baseIndex: startLine,
      baseOffset: 0,
      extentIndex: endLine,
      extentOffset:
          controller.codeLines[endLine].length,
    );

    controller.runRevocableOp(() {
      controller.replaceSelection(newLines.join('\n'), selectionToReplace);
    });
  }

  Future<void> showLanguageSelectionDialog() async {
    final allLanguages = Languages.all;

    final selectedLanguageId = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
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
                    selected: lang.id == _languageConfig.id,
                    onTap: () => Navigator.pop(ctx, lang.id),
                  );
                },
              ),
            ),
          ),
    );

    if (selectedLanguageId != null &&
        selectedLanguageId != _languageConfig.id) {
      setState(() {
        _languageConfig = Languages.getById(selectedLanguageId);
        _updateInternalConfig();
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
    return CodeEditorUtils.buildHighlightingSpan(
      context: context,
      index: index,
      codeLine: codeLine,
      textSpan: textSpan,
      style: style,
      bracketHighlightState: _bracketHighlightNotifier.value,
      onLinkTap: _onLinkTap,
      onColorTap: _onColorCodeTap,
      parser: _cachedParser,
      enableBracketMatching: _enableBracketMatching,
      enableColorPreviews: _enableColorPreviews,
      enableLinks: _enableLinks,
      resourceManager: _resourceManager,
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
      prev,
      next,
    ) {
      if (prev != next && next != null) {
        setState(() {
          final newLanguageConfig = Languages.getForFile(next);
          if (newLanguageConfig.id != _languageConfig.id) {
            _languageConfig = newLanguageConfig;
          }
          _updateInternalConfig();
        });
      }
    });

    ref.listen(effectiveSettingsProvider, (previous, next) {
      setState(() {
        _updateInternalConfig();
      });
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
