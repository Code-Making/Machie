// =========================================
// FILE: lib/editor/plugins/code_editor/code_editor_widgets.dart
// =========================================
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart'; // <-- FIX: ADD THIS IMPORT for ValueListenable
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import 'code_themes.dart';
import 'code_editor_models.dart';
import 'code_editor_logic.dart';
import 'code_editor_state.dart';
import 'code_editor_plugin.dart'; // ADDED: For type cast
import 'code_find_panel_view.dart';
import 'goto_line_dialog.dart'; // <-- ADD THIS IMPORT

import '../../editor_tab_models.dart';
import '../../tab_state_manager.dart';

import '../../../app/app_notifier.dart';
import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../command/command_models.dart'; // ADDED: For Command class
import '../../../editor/plugins/editor_command_context.dart'; // ADDED: For CommandButton
import '../../../command/command_widgets.dart'; // ADDED: For CommandButton
import '../../../editor/services/editor_service.dart';
import '../../../settings/settings_notifier.dart';

import '../../../data/repositories/project_repository.dart';
import '../../../utils/toast.dart';

import 'code_editor_hot_state_dto.dart'; // For serializeHotState


// ... (BracketHighlightState is unchanged) ...
class BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final Set<int> highlightedLines;
  const BracketHighlightState({
    this.bracketPositions = const {},
    this.highlightedLines = const {},
  });
}

class CodeEditorMachine extends EditorWidget {
  @override
  final CodeEditorTab tab;

  // --- FIX: Add the required super constructor call ---
  const CodeEditorMachine({
    required GlobalKey<CodeEditorMachineState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  CodeEditorMachineState createState() => CodeEditorMachineState();
}

class CodeEditorMachineState extends EditorWidgetState<CodeEditorMachine> {
  // --- STATE ---
  late final CodeLineEditingController controller;
  late final FocusNode _focusNode;
  late final CodeFindController findController;
  CodeChunkController? _chunkController;
  CodeLinePosition? _markPosition;

  BracketHighlightState _bracketHighlightState = const BracketHighlightState();

  late CodeCommentFormatter _commentFormatter;
  late String? _languageKey;
  
  late CodeEditorStyle _style;
  late List<PatternRecognizer> _patternRecognizers;


  bool _wasSelectionActive = false;
  
  late String? _baseContentHash; // <-- ADDED


  // The public getters for canUndo/canRedo are now gone.
  // The private methods remain.
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
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _baseContentHash = widget.tab.initialBaseContentHash;

    final fileUri = ref.read(tabMetadataProvider)[widget.tab.id]?.file.uri;
    if (fileUri == null) {
      throw StateError("Could not find metadata for tab ID: ${widget.tab.id}");
    }

    _languageKey = widget.tab.initialLanguageKey ?? CodeThemes.inferLanguageKey(fileUri);
    _commentFormatter = CodeEditorLogic.getCommentFormatter(fileUri);

    controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(widget.tab.initialContent),
      spanBuilder: _buildHighlightingSpan,
    );    findController = CodeFindController(controller);
    
    findController.addListener(syncCommandContext);
    controller.addListener(_onControllerChange);
    controller.dirty.addListener(_onDirtyStateChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        syncCommandContext();
        if (widget.tab.cachedContent != null) {
          controller.text = widget.tab.cachedContent!;
        }
      }
    });
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateStyleAndRecognizers();
  }

  @override
  void didUpdateWidget(covariant CodeEditorMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFileUri = ref.read(tabMetadataProvider)[oldWidget.tab.id]?.file.uri;
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
    final List<FontFeature>? fontFeatures =
        enableLigatures
            ? null
            : const [
              FontFeature.disable('liga'),
              FontFeature.disable('clig'),
              FontFeature.disable('calt'),
            ];

    _patternRecognizers = _buildPatternRecognizers();

    _style = CodeEditorStyle(
      fontHeight: codeEditorSettings?.fontHeight,
      fontSize: codeEditorSettings?.fontSize ?? 12.0,
      fontFamily: codeEditorSettings?.fontFamily ?? 'JetBrainsMono',
      fontFeatures: fontFeatures,
      patternRecognizers: _patternRecognizers,
      codeTheme: CodeHighlightTheme(
        theme:
            CodeThemes.availableCodeThemes[selectedThemeName] ??
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

    // The total number of lines is the length of codeLines.
    // The maximum valid line *number* for the user is this length.
    final int maxLines = controller.codeLines.length;
    final int currentLine = controller.selection.start.index;

    final int? targetLineIndex = await showDialog<int>(
      context: context,
      builder:
          (ctx) => GoToLineDialog(maxLine: maxLines, currentLine: currentLine),
    );

    if (targetLineIndex != null) {
      // THE FIX:
      // 1. Create a CodeLinePosition for the start of the target line.
      final CodeLinePosition targetPosition = CodeLinePosition(
        index: targetLineIndex,
        offset: 0,
      );

      // 2. Move the cursor by setting the controller's selection.
      controller.selection = CodeLineSelection.fromPosition(
        position: targetPosition,
      );

      // 3. Ensure the new cursor position is visible.
      controller.makePositionCenterIfInvisible(targetPosition);
    }
  }

  void selectOrExpandLines() {
    final CodeLineSelection currentSelection = controller.selection;

    // THIS IS THE FIX: Convert the CodeLines iterable to a List.
    final List<CodeLine> lines = controller.codeLines.toList();

    // A "full line" selection is defined as starting at offset 0 of one line
    // and ending at offset 0 of a subsequent line. This is a robust check
    // for selections created by triple-clicking or by this command itself.
    final bool isAlreadyFullLineSelection =
        currentSelection.start.offset == 0 &&
        currentSelection.end.offset == 0 &&
        currentSelection.end.index > currentSelection.start.index;

    if (isAlreadyFullLineSelection) {
      // BEHAVIOR 2: The selection is already full lines, so expand to the next line.
      // We can expand as long as the end of our selection is not at the very end of the document.
      if (currentSelection.end.index < lines.length) {
        // Create a new selection that keeps the same start but moves the end
        // to the beginning of the line *after* the next one.
        controller.selection = currentSelection.copyWith(
          extentIndex: currentSelection.end.index + 1,
          extentOffset: 0,
        );
      }
    } else {
      // BEHAVIOR 1: The selection is a cursor or partial. Expand to full lines.
      // The new selection starts at the beginning of the first selected line.
      final newStartIndex = currentSelection.start.index;

      // The new selection ends at the beginning of the line AFTER the last selected line.
      // We use clamp to prevent going past the end of the document.
      final newEndIndex = (currentSelection.end.index + 1).clamp(
        0,
        lines.length,
      );

      controller.selection = CodeLineSelection(
        baseIndex: newStartIndex,
        baseOffset: 0,
        extentIndex: newEndIndex,
        extentOffset: 0,
      );
    }

    // This is crucial to update the UI (like the selection app bar).
    _onControllerChange();
  }

  /// Expands the selection to the nearest code chunk (e.g., a foldable block).
  void selectCurrentChunk() {
    // We must have a reference to the chunk controller, which is provided
    // by the editor's indicatorBuilder.
    if (_chunkController == null) return;

    // The controller method requires the list of available chunks.
    controller.selectChunk(_chunkController!.value);
    _onControllerChange();
  }

  void extendSelection() {
    final CodeLineSelection currentSelection = controller.selection;
    CodeLineSelection? newSelection;

    // 1. Find the smallest block that contains the current selection.
    final enclosingBlock = _findSmallestEnclosingBlock(currentSelection);

    if (enclosingBlock != null) {
      // 2. Decide what to select based on the hierarchy.
      if (currentSelection == enclosingBlock.contents) {
        // If we already have the contents selected, expand to the full block (including delimiters).
        newSelection = enclosingBlock.full;
      } else {
        // Otherwise (cursor is collapsed or selection is partial), select the contents.
        newSelection = enclosingBlock.contents;
      }
    }

    // 3. Apply the new selection if it's different.
    if (newSelection != null && newSelection != currentSelection) {
      controller.selection = newSelection;
      _onControllerChange();
    }
  }

  /// Finds the smallest block that fully contains the [selection].
  /// Returns a record containing the full block selection and the content-only selection.
  ({CodeLineSelection full, CodeLineSelection contents})?
  _findSmallestEnclosingBlock(CodeLineSelection selection) {
    const List<String> openDelimiters = ['(', '[', '{', '"', "'"];

    // Start our search scanning backwards from the beginning of the user's selection.
    CodeLinePosition scanPos = selection.start;

    while (true) {
      final char = _getChar(scanPos);

      // Is the character at our scan position an opening delimiter?
      if (char != null && openDelimiters.contains(char)) {
        final openDelimiterPos = scanPos;
        final openChar = char;
        final closeChar = _getMatchingDelimiterChar(openChar);

        // We found a candidate. Now, verify it by finding its real partner.
        final closeDelimiterPos = _findMatchingDelimiter(
          openDelimiterPos,
          openChar,
          closeChar,
        );

        if (closeDelimiterPos != null) {
          // We have a valid pair. Create a selection for the full block.
          final fullBlockSelection = CodeLineSelection(
            baseIndex: openDelimiterPos.index,
            baseOffset: openDelimiterPos.offset,
            extentIndex: closeDelimiterPos.index,
            extentOffset: closeDelimiterPos.offset + 1,
          );

          // The final, critical check: Does this valid block contain our original selection?
          if (fullBlockSelection.contains(selection)) {
            // Success! This is the smallest valid block.
            final contentSelection = CodeLineSelection(
              baseIndex: openDelimiterPos.index,
              baseOffset: openDelimiterPos.offset + 1,
              extentIndex: closeDelimiterPos.index,
              extentOffset: closeDelimiterPos.offset,
            );
            return (full: fullBlockSelection, contents: contentSelection);
          }
        }
      }

      // If we didn't find a valid block, move our scan position one character to the left.
      final prevPos = _getPreviousPosition(scanPos);
      if (prevPos == scanPos) {
        break; // We've reached the beginning of the document.
      }
      scanPos = prevPos;
    }

    return null; // No enclosing block was found.
  }

  /// Finds the position of a matching closing delimiter, respecting nested pairs.
  /// This is the same trusted function used for bracket highlighting.
  CodeLinePosition? _findMatchingDelimiter(
    CodeLinePosition start,
    String open,
    String close,
  ) {
    int stack = 1;
    CodeLinePosition currentPos = _getNextPosition(start);

    while (true) {
      final char = _getChar(currentPos);
      if (char != null) {
        // For non-quote pairs, handle nesting.
        if (char == open && open != close) {
          stack++;
        } else if (char == close) {
          stack--;
        }
        if (stack == 0) {
          return currentPos;
        }
      }

      final nextPos = _getNextPosition(currentPos);
      if (nextPos == currentPos) {
        break; // Reached end of document
      }
      currentPos = nextPos;
    }
    return null; // No match found
  }

  // --- UTILITY HELPERS (Safe and Simple) ---

  /// Given an opening delimiter, returns its closing counterpart.
  String _getMatchingDelimiterChar(String openChar) {
    const Map<String, String> pairs = {
      '(': ')',
      '[': ']',
      '{': '}',
      '"': '"',
      "'": "'",
    };
    return pairs[openChar]!;
  }

  /// Gets the character at a given position, returning null on failure.
  String? _getChar(CodeLinePosition pos) {
    if (pos.index < 0 || pos.index >= controller.codeLines.length) return null;
    final line = controller.codeLines[pos.index].text;
    if (pos.offset < 0 || pos.offset >= line.length) return null;
    return line[pos.offset];
  }

  /// Gets the character position immediately before the given one.
  CodeLinePosition _getPreviousPosition(CodeLinePosition pos) {
    if (pos.offset > 0) {
      return CodeLinePosition(index: pos.index, offset: pos.offset - 1);
    }
    if (pos.index > 0) {
      final prevLine = controller.codeLines[pos.index - 1].text;
      return CodeLinePosition(index: pos.index - 1, offset: prevLine.length);
    }
    return pos; // At start of document
  }

  /// Gets the character position immediately after the given one.
  CodeLinePosition _getNextPosition(CodeLinePosition pos) {
    final line = controller.codeLines[pos.index].text;
    if (pos.offset < line.length) {
      return CodeLinePosition(index: pos.index, offset: pos.offset + 1);
    }
    if (pos.index < controller.codeLines.length - 1) {
      return CodeLinePosition(index: pos.index + 1, offset: 0);
    }
    return pos; // At end of document
  }

  // --- NEW PUBLIC METHODS for Commands ---
  void showFindPanel() {
    findController.findMode();
  }

  void showReplacePanel() {
    findController.replaceMode();
  }
  
  // PATTERN RECOGNIZERS
List<PatternRecognizer> _buildPatternRecognizers() {
  final fileUri = ref.read(tabMetadataProvider)[widget.tab.id]?.file.uri;
  if (fileUri == null) return [];

  // Using the RegExp you confirmed works.
  final importRegex = RegExp(r"import\s+?(.*?);");

  return [
    PatternRecognizer(
      pattern: importRegex,
      builder: (match, spans) {
        final fullMatchText = match.group(0); // e.g., "import './path.dart';"
        final pathWithQuotes = match.group(1); // e.g., "'./path.dart'"

        // Safeguards
        if (fullMatchText == null || pathWithQuotes == null || pathWithQuotes.length < 2) {
          return TextSpan(children: spans);
        }

        // Extract the raw path by removing the quotes
        final rawPath = pathWithQuotes.substring(1, pathWithQuotes.length - 1);

        // Find the start index of the raw path within the full matched string.
        // This is safer than assuming positions.
        final rawPathStartIndex = fullMatchText.indexOf(rawPath);

        if (rawPathStartIndex == -1) {
           return TextSpan(children: spans);
        }
        
        final rawPathEndIndex = rawPathStartIndex + rawPath.length;

        // Split the full match into three parts around the raw path
        final partBeforePath = fullMatchText.substring(0, rawPathStartIndex);
        final partAfterPath = fullMatchText.substring(rawPathEndIndex);

        // Get a base style from the underlying syntax-highlighted spans.
        final baseStyle = spans.firstOrNull?.style;
// final secondStyle = spans.length > 1 ? spans[1].style : null;
final secondStyle = spans.firstOrNull?.elementAtOrNull(1)?.style;

        return TextSpan(
          style: baseStyle,
          children: [
            // Part 1: The part before the path (e.g., "import '") - not tappable
            TextSpan(text: partBeforePath),
            
            // Part 2: The path itself - styled and tappable
            TextSpan(
              text: rawPath,
              style: TextStyle(
                // color: Colors.cyan[300],
                color: secondStyle?.color ?? Colors.cyan[300],
                decoration: TextDecoration.underline,
                decorationColor: secondStyle?.color?.withOpacity(0.6) ?? Colors.cyan[300]?.withOpacity(0.5),
              ),
              recognizer: TapGestureRecognizer()..onTap = () => _onImportTap(rawPath),
            ),
            
            // Part 3: The part after the path (e.g., "';") - not tappable
            TextSpan(text: partAfterPath),
          ],
        );
      },
    ),
  ];
}

  // NEW: The handler for when a recognized import path is tapped.
  void _onImportTap(String relativePath) async {
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final fileHandler = ref.read(projectRepositoryProvider)?.fileHandler;
    final currentFileMetadata = ref.read(tabMetadataProvider)[widget.tab.id];

    if (fileHandler == null || currentFileMetadata == null) return;
    
    try {
      final currentDirectoryUri = fileHandler.getParentUri(currentFileMetadata.file.uri);
      final pathSegments = [...currentDirectoryUri.split('%2F'), ...relativePath.split('/')];
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

  // NEW METHOD: Handles changes from controller.dirty
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

    // UI-specific updates that require setState
    setState(() {
      _bracketHighlightState = _calculateBracketHighlights();
    });

    // Central state synchronization
    syncCommandContext();

    // Caching side-effect
    if (controller.dirty.value) {
      final project = ref.read(appNotifierProvider).value?.currentProject;
      if (project != null) {
        ref
            .read(editorServiceProvider)
            .updateAndCacheDirtyTab(project, widget.tab);
      }
    }
  }

  /// Returns the current unsaved state of the editor for caching.
  Map<String, dynamic> getHotState() {
    return {
      'content': controller.text,
      'languageKey': _languageKey,
      'baseContentHash': _baseContentHash, // <-- ADDED
    };
  }


  
  @override
  void syncCommandContext() {
    if (!mounted) return;

    final hasSelection = !controller.selection.isCollapsed;
    Widget? appBarOverride;

    // Priority 1: If the find panel is active, its app bar takes precedence.
    if (findController.value != null) {
      appBarOverride = CodeFindAppBar(controller: findController);
    } 
    // Priority 2: If no find panel, but there is a selection, show the selection bar.
    else if (hasSelection) {
      appBarOverride = _buildSelectionAppBar();
    }
    
    final newContext = CodeEditorCommandContext(
      canUndo: controller.canUndo,
      canRedo: controller.canRedo,
      hasSelection: hasSelection,
      hasMark: _markPosition != null,
      appBarOverride: appBarOverride,
    );
    
    ref.read(commandContextProvider(widget.tab.id).notifier).state = newContext;
  }
  
  

  // ... (setMark, selectToMark, toggleComments, etc. are unchanged as they work on the controller) ...
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
        _comparePositions(_markPosition!, currentPosition) < 0
            ? _markPosition!
            : currentPosition;
    final end =
        _comparePositions(_markPosition!, currentPosition) < 0
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
      builder:
          (ctx) => AlertDialog(
            title: const Text('Select Language'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: CodeThemes.languageNameToModeMap.keys.length,
                itemBuilder: (context, index) {
                  final langKey = CodeThemes.languageNameToModeMap.keys
                      .elementAt(index);
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
      // THE FIX: Mark the tab as dirty so the cache system will save this change.
      ref.read(editorServiceProvider).markCurrentTabDirty();
    }
  }

  // ... (bracket highlighting logic is unchanged) ...
  BracketHighlightState _calculateBracketHighlights() {
    final selection = controller.selection;
    if (!selection.isCollapsed) {
      return const BracketHighlightState();
    }
    final position = selection.base;
    final brackets = {'(': ')', '[': ']', '{': '}'};
    final line = controller.codeLines[position.index].text;
    Set<CodeLinePosition> newPositions = {};
    Set<int> newHighlightedLines = {};
    for (int offset in [position.offset, position.offset - 1]) {
      if (offset >= 0 && offset < line.length) {
        final char = line[offset];
        if (brackets.keys.contains(char) || brackets.values.contains(char)) {
          final currentPosition = CodeLinePosition(
            index: position.index,
            offset: offset,
          );
          final matchPosition = _findMatchingBracket(
            controller.codeLines,
            currentPosition,
            brackets,
          );
          if (matchPosition != null) {
            newPositions.add(currentPosition);
            newPositions.add(matchPosition);
            newHighlightedLines.add(currentPosition.index);
            newHighlightedLines.add(matchPosition.index);
            break;
          }
        }
      }
    }
    return BracketHighlightState(
      bracketPositions: newPositions,
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
    final isOpen = brackets.keys.contains(char);
    final target =
        isOpen
            ? brackets[char]
            : brackets.keys.firstWhere(
              (k) => brackets[k] == char,
              orElse: () => '',
            );
    if (target == null || target.isEmpty) return null;
    int stack = 1;
    int index = position.index;
    int offset = position.offset;
    final direction = isOpen ? 1 : -1;
    while (true) {
      offset += direction;
      if (direction > 0) {
        if (offset >= codeLines[index].text.length) {
          index++;
          if (index >= codeLines.length) return null;
          offset = 0;
        }
      } else {
        if (offset < 0) {
          index--;
          if (index < 0) return null;
          offset = codeLines[index].text.length - 1;
        }
      }
      final currentChar = codeLines[index].text[offset];
      if (currentChar == char) {
        stack++;
      } else if (currentChar == target) {
        stack--;
      }
      if (stack == 0) {
        return CodeLinePosition(index: index, offset: offset);
      }
    }
  }

  int _comparePositions(CodeLinePosition a, CodeLinePosition b) {
    if (a.index < b.index) return -1;
    if (a.index > b.index) return 1;
    return a.offset.compareTo(b.offset);
  }

  TextSpan _buildHighlightingSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final highlightState = _bracketHighlightState;
    final highlightPositions =
        highlightState.bracketPositions
            .where((pos) => pos.index == index)
            .map((pos) => pos.offset)
            .toSet();

    if (highlightPositions.isEmpty) {
      return textSpan;
    }

    final builtSpans = <TextSpan>[];
    int currentPosition = 0;

    void processSpan(TextSpan span) {
      final text = span.text ?? '';
      final spanStyle = span.style ?? style;
      int lastSplit = 0;

      for (int i = 0; i < text.length; i++) {
        final absolutePosition = currentPosition + i;
        if (highlightPositions.contains(absolutePosition)) {
          if (i > lastSplit) {
            builtSpans.add(
              TextSpan(text: text.substring(lastSplit, i), style: spanStyle),
            );
          }
          builtSpans.add(
            TextSpan(
              text: text[i],
              style: spanStyle.copyWith(
                backgroundColor: Colors.yellow.withValues(alpha: 0.3),
                fontWeight: FontWeight.bold,
              ),
            ),
          );
          lastSplit = i + 1;
        }
      }
      if (lastSplit < text.length) {
        builtSpans.add(
          TextSpan(text: text.substring(lastSplit), style: spanStyle),
        );
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
    return TextSpan(children: builtSpans, style: style);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // If our main editor focus node doesn't have the *primary* focus,
    // then some other widget (like the find panel's text field) does.
    // In that case, we must ignore the event and let the other widget handle it.
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
    // The ref.listen is a side-effect, it's fine to keep it here.
    ref.listen(tabMetadataProvider.select((m) => m[widget.tab.id]?.file.uri), (
      previous,
      next,
    ) {
      if (previous != next && next != null) {
        setState(() {
          final newLanguageKey = CodeThemes.inferLanguageKey(next);
          if (newLanguageKey != _languageKey) {
            _languageKey = newLanguageKey;
            _updateStyleAndRecognizers(); // Rebuild style for new language
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
        // The builders are lightweight functions, they are fine here.
        findBuilder: (context, controller, readOnly) {
          return CodeFindPanelView(
            controller: controller,
            iconSelectedColor: colorScheme.primary,
            iconColor: colorScheme.onSurface.withOpacity(0.6),
            readOnly: readOnly,
          );
        },
        commentFormatter: _commentFormatter,
        verticalScrollbarWidth: 16.0,
        scrollbarBuilder: (context, child, details) {
          return _GrabbableScrollbar(
            details: details,
            thickness: 16.0,
            child: child,
          );
        },
        indicatorBuilder: (context, editingController, chunkController, notifier) {
          _chunkController = chunkController;
          return CustomEditorIndicator(
            controller: editingController,
            chunkController: chunkController,
            notifier: notifier,
            bracketHighlightState: _bracketHighlightState,
          );
        },
        // All expensive objects are now simple variable lookups.
        style: _style,
        wordWrap: ref.watch(
          settingsProvider.select(
            (s) => (s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?)?.wordWrap ?? false,
          ),
        ),
      ),
    );
  }
}

// ... (CustomEditorIndicator and _CustomLineNumberWidget are unchanged) ...
class CustomEditorIndicator extends StatelessWidget {
  final CodeLineEditingController controller;
  final CodeChunkController chunkController;
  final CodeIndicatorValueNotifier notifier;
  final BracketHighlightState bracketHighlightState;

  const CustomEditorIndicator({
    super.key,
    required this.controller,
    required this.chunkController,
    required this.notifier,
    required this.bracketHighlightState,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Row(
        children: [
          _CustomLineNumberWidget(
            controller: controller,
            notifier: notifier,
            highlightedLines: bracketHighlightState.highlightedLines,
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

class _CustomLineNumberWidget extends StatelessWidget {
  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final Set<int> highlightedLines;

  const _CustomLineNumberWidget({
    required this.controller,
    required this.notifier,
    required this.highlightedLines,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<CodeIndicatorValue?>(
      valueListenable: notifier,
      builder: (context, value, child) {
        return DefaultCodeLineNumber(
          controller: controller,
          notifier: notifier,
          textStyle: TextStyle(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
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

// in lib/editor/plugins/code_editor/code_editor_widgets.dart

class CodeEditorSelectionAppBar extends ConsumerWidget {
  const CodeEditorSelectionAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolbar = CommandToolbar(
      position: CodeEditorPlugin.selectionToolbar,
      direction: Axis.horizontal,
    );

    return Material(
      elevation: 4.0,
      color: Theme.of(context).appBarTheme.backgroundColor,
      child: SafeArea(
        child: Container(
          height: Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          // THE FIX: Wrap the command toolbar in a scrollable widget.
          // Using `reverse: true` keeps the content anchored to the right side.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: CodeEditorTapRegion(child: toolbar),
          ),
        ),
      ),
    );
  }
}

// You can place this helper widget at the bottom of your file.
class _GrabbableScrollbar extends StatefulWidget {
  const _GrabbableScrollbar({
    required this.details,
    required this.thickness,
    required this.child,
  });

  final ScrollableDetails details;
  final double thickness;
  final Widget child;

  @override
  State<_GrabbableScrollbar> createState() => _GrabbableScrollbarState();
}

class _GrabbableScrollbarState extends State<_GrabbableScrollbar> {
  // This state variable will control the scrollbar's visibility.
  bool _isScrolling = false;

  @override
  Widget build(BuildContext context) {
    // Listen for scroll notifications bubbling up from the editor.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          // A scroll has started, so make the scrollbar visible.
          setState(() {
            _isScrolling = true;
          });
        } else if (notification is ScrollEndNotification) {
          // The scroll has ended, so hide the scrollbar after a short delay.
          // The delay prevents it from disappearing instantly if the user flings.
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() {
                _isScrolling = false;
              });
            }
          });
        }
        // Allow the notification to continue bubbling up.
        return false;
      },
      child: RawScrollbar(
        controller: widget.details.controller,

        // --- The Key Change ---
        // The visibility is now controlled by our state variable.
        thumbVisibility: _isScrolling,

        // ----------------------
        thickness: widget.thickness,
        interactive: true,
        radius: Radius.circular(widget.thickness / 2),

        // Let the editor's scroll behavior handle the physics.
        // We are only concerned with the UI here.
        child: widget.child,
      ),
    );
  }
}
