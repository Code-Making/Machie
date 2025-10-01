// =========================================
// FILE: lib/editor/plugins/code_editor/code_editor_widgets.dart
// =========================================

// lib/plugins/code_editor/code_editor_widgets.dart
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

import '../../tab_state_manager.dart';
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart'; // ADDED: For Command class
import '../../../command/command_widgets.dart'; // ADDED: For CommandButton
import '../../../editor/services/editor_service.dart';
import '../../../settings/settings_notifier.dart';

// ... (BracketHighlightState is unchanged) ...
class BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final Set<int> highlightedLines;
  const BracketHighlightState({
    this.bracketPositions = const {},
    this.highlightedLines = const {},
  });
}

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeEditorTab tab;

  const CodeEditorMachine({super.key, required this.tab});

  @override
  CodeEditorMachineState createState() => CodeEditorMachineState();
}

class CodeEditorMachineState extends ConsumerState<CodeEditorMachine> {
  // --- STATE ---
  late final CodeLineEditingController controller;
  late final FocusNode _focusNode;
  late final CodeFindController findController;
  CodeChunkController? _chunkController;
  CodeLinePosition? _markPosition;

  BracketHighlightState _bracketHighlightState =
      const BracketHighlightState();

  late CodeCommentFormatter _commentFormatter;
  late String? _languageKey;

  bool _wasSelectionActive = false;

  // --- PUBLIC PROPERTIES (for the command system) ---
  // isDirty is no longer needed here; the command gets it from the provider.
  //bool get canUndo => controller.canUndo;
  //bool get canRedo => controller.canRedo;
  //bool get hasMark => _markPosition != null;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();

    // REFACTORED: Get the file URI from the metadata provider using the tab's stable ID.
    final fileUri = ref.read(tabMetadataProvider)[widget.tab.id]?.file.uri;
    if (fileUri == null) {
      // This should not happen in a normal flow. Handle gracefully.
      throw StateError("Could not find metadata for tab ID: ${widget.tab.id}");
    }

    _languageKey = widget.tab.initialLanguageKey ?? CodeThemes.inferLanguageKey(fileUri);
    _commentFormatter = CodeEditorLogic.getCommentFormatter(fileUri);

    controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(widget.tab.initialContent),
      spanBuilder: _buildHighlightingSpan,
    );

    findController = CodeFindController(controller);

    controller.addListener(_onControllerChange);
    controller.dirty.addListener(_onDirtyStateChange); // <-- NEW LISTENER
    // This listener is the key to the whole feature.
    // It watches for a change in the 'hasSelection' state and does something
    // (a "side effect") without causing this widget to rebuild.
    _updateStateProvider();
  }

  @override
  void didUpdateWidget(covariant CodeEditorMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This is now the correct way to react to a file rename.
    // The widget itself is reused, but we listen for changes in the metadata provider.
    final oldFileUri =
        ref.read(tabMetadataProvider)[oldWidget.tab.id]?.file.uri;
    final newFileUri = ref.read(tabMetadataProvider)[widget.tab.id]?.file.uri;

    if (newFileUri != null && newFileUri != oldFileUri) {
      // A rename has occurred. Update internal state that depends on the URI.
      setState(() {
        _languageKey = CodeThemes.inferLanguageKey(newFileUri);
        _commentFormatter = CodeEditorLogic.getCommentFormatter(newFileUri);
      });
    }
  }

  // NEW METHOD: A helper to build the contextual AppBar.
  Widget _buildSelectionAppBar() {
    return const CodeEditorSelectionAppBar();
  }

  @override
  void dispose() {
    // Check if an override is active and clear it. This is good practice.
    if (_wasSelectionActive) {
      ref.read(appNotifierProvider.notifier).clearAppBarOverride();
    }
    findController.dispose();
    controller.dirty.removeListener(_onDirtyStateChange);
    controller.removeListener(_onControllerChange);
    controller.dispose();
    _focusNode.dispose();
    super.dispose();
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

  /// Selects the full line where the cursor's selection starts.
  void selectCurrentLine() {
    // Get the line index of where the selection begins.
    final int currentIndex = controller.selection.start.index;
    controller.selectLine(currentIndex);
    // Notify the app that the selection has changed (e.g., for the contextual app bar)
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

    // 1. First, handle UI-specific updates that need setState.
    setState(() {
      _bracketHighlightState = _calculateBracketHighlights();
    });

    // 2. Then, update the reactive state provider for commands.
    _updateStateProvider();

    // 3. Now, handle the AppBar override side-effect.
    final isSelectionActive = !controller.selection.isCollapsed;

    // Only trigger the side-effect if the selection state has *changed*.
    if (isSelectionActive != _wasSelectionActive) {
      final appNotifier = ref.read(appNotifierProvider.notifier);
      if (isSelectionActive) {
        appNotifier.setAppBarOverride(_buildSelectionAppBar());
      } else {
        appNotifier.clearAppBarOverride();
      }
      // Update our local tracker to the new state.
      _wasSelectionActive = isSelectionActive;
    }
  }

  Future<void> save() async {
    final project = ref.read(appNotifierProvider).value!.currentProject!;
    final success = await ref
        .read(editorServiceProvider)
        .saveCurrentTab(project, content: controller.text);

    // If the save was successful, we tell the controller that its
    // current state is the new "clean" baseline.
    if (success) {
      controller.markCurrentStateAsClean(); // <-- USE NEW API
    }
  }

  /// Returns the current unsaved state of the editor for caching.
  Map<String, dynamic> getHotState() {
    // THE FIX: Include the language key in the state map.
    return {
      'content': controller.text,
      'languageKey': _languageKey,
    };
  }

  // NEW METHOD: Centralizes updating the state provider.
  void _updateStateProvider() {
    ref
        .read(codeEditorStateProvider(widget.tab.id).notifier)
        .update(
          canUndo: controller.canUndo,
          canRedo: controller.canRedo,
          hasMark: _markPosition != null,
          hasSelection: !controller.selection.isCollapsed, // <-- THE TRIGGER
        );
  }

  // ... (setMark, selectToMark, toggleComments, etc. are unchanged as they work on the controller) ...
  void setMark() {
    setState(() {
      _markPosition = controller.selection.base;
    });
    _updateStateProvider();
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
    // ... (ref.listen and settings logic at the top of build is unchanged) ...
    ref.listen(tabMetadataProvider.select((m) => m[widget.tab.id]?.file.uri), (
      previous,
      next,
    ) {
      if (previous != next && next != null) {
        setState(() {
          _languageKey = CodeThemes.inferLanguageKey(next);
          _commentFormatter = CodeEditorLogic.getCommentFormatter(next);
        });
      }
    });

    final codeEditorSettings = ref.watch(
      settingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    );
    final selectedThemeName = codeEditorSettings?.themeName ?? 'Atom One Dark';

    // --- THIS IS THE MODIFIED SECTION ---
    return Focus(
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: CodeEditor(
        controller: controller,
        focusNode: _focusNode,
        findController: findController,
        findBuilder: (context, controller, readOnly) {
          return CodeFindPanelView(controller: controller, readOnly: readOnly);
        },
        commentFormatter: _commentFormatter,
        verticalScrollbarWidth: 16.0,
        scrollbarBuilder: (context, child, details) {
    // We use a StatefulWidget here to manage the visibility state.
    // A simple StatefulWidget is cleaner than a StatefulBuilder for this.
    return _GrabbableScrollbar(
      details: details,
      thickness: 16.0, // Your desired thickness
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
            bracketHighlightState: _bracketHighlightState,
          );
        },
        style: CodeEditorStyle(
          fontHeight: codeEditorSettings?.fontHeight,
          fontSize: codeEditorSettings?.fontSize ?? 12.0,
          fontFamily: codeEditorSettings?.fontFamily ?? 'JetBrainsMono',
          codeTheme: CodeHighlightTheme(
            theme:
                CodeThemes.availableCodeThemes[selectedThemeName] ??
                CodeThemes.availableCodeThemes['Atom One Dark']!,
            languages: CodeThemes.getHighlightThemeMode(_languageKey),
          ),
        ),
        wordWrap: codeEditorSettings?.wordWrap ?? false,
      ),
    );
    // --- END OF MODIFIED SECTION ---
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

class CodeEditorSelectionAppBar extends StatelessWidget {
  const CodeEditorSelectionAppBar({super.key});

  @override
  Widget build(BuildContext context) {
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
          // THE FIX: The layout is now a Row containing a Spacer and an Expanded
          // SingleChildScrollView, which makes the toolbar right-aligned and scrollable.
          child: Row(
            children: [
              const Spacer(),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // Reversing the scroll view makes it feel more natural for a
                  // right-aligned toolbar that might overflow to the left.
                  reverse: true,
                  child: CodeEditorTapRegion(child: toolbar),
                ),
              ),
            ],
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