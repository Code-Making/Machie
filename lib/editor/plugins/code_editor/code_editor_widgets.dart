// =========================================
// FILE: lib/editor/plugins/code_editor/code_editor_widgets.dart
// =========================================

// lib/plugins/code_editor/code_editor_widgets.dart
import 'dart:io';
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

import '../../tab_state_manager.dart';
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart'; // ADDED: For Command class
import '../../../command/command_widgets.dart'; // ADDED: For CommandButton
import '../../../editor/services/editor_service.dart';
import '../../../settings/settings_notifier.dart';

// ... (_BracketHighlightState is unchanged) ...
class _BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final Set<int> highlightedLines;
  const _BracketHighlightState({
    this.bracketPositions = const {},
    this.highlightedLines = const {},
  });
}

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeEditorTab tab;

  const CodeEditorMachine({
    super.key,
    required this.tab,
  });

  @override
  CodeEditorMachineState createState() => CodeEditorMachineState();
}

class CodeEditorMachineState extends ConsumerState<CodeEditorMachine> {
  // --- STATE ---
  late final CodeLineEditingController controller;
  late final FocusNode _focusNode;
  late final CodeFindController findController;

  CodeLinePosition? _markPosition;
  _BracketHighlightState _bracketHighlightState =
      const _BracketHighlightState();

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
    
    _languageKey = CodeThemes.inferLanguageKey(fileUri);
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
    final oldFileUri = ref.read(tabMetadataProvider)[oldWidget.tab.id]?.file.uri;
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
    final plugin = widget.tab.plugin as CodeEditorPlugin;
    
    // We find all our commands by ID from the plugin's command list.
    final allCommands = plugin.getCommands();
    final cutCommand = allCommands.firstWhere((c) => c.id == 'cut');
    final copyCommand = allCommands.firstWhere((c) => c.id == 'copy');
    final pasteCommand = allCommands.firstWhere((c) => c.id == 'paste');
    final commentCommand = allCommands.firstWhere((c) => c.id == 'toggle_comment');     // <-- ADDED
    final moveLineUpCommand = allCommands.firstWhere((c) => c.id == 'move_line_up');   // <-- ADDED
    final moveLineDownCommand = allCommands.firstWhere((c) => c.id == 'move_line_down'); // <-- ADDED

    return CodeEditorSelectionAppBar(
      cutCommand: cutCommand,
      copyCommand: copyCommand,
      pasteCommand: pasteCommand,
      commentCommand: commentCommand,          // <-- ADDED
      moveLineUpCommand: moveLineUpCommand,      // <-- ADDED
      moveLineDownCommand: moveLineDownCommand,  // <-- ADDED
    );
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
  
  void extendSelection() {
    final CodeLineSelection currentSelection = controller.selection;

    // If the cursor is just a point, the first step is to select the current word.
    if (currentSelection.isCollapsed) {
      final CodeLineSelection? wordSelection = _findWordBoundaryAt(currentSelection.start);
      if (wordSelection != null) {
        controller.selection = wordSelection;
        _onControllerChange(); // Notify UI of selection change
        return;
      }
    }

    // If there's already a selection, try to expand to the nearest enclosing block.
    final CodeLineSelection? blockSelection = _findEnclosingBlock(currentSelection);
    if (blockSelection != null && blockSelection != currentSelection) {
      controller.selection = blockSelection;
      _onControllerChange();
      return;
    }

    // As a final fallback, expand the selection to encompass the full lines.
    final CodeLineSelection lineSelection = _expandToFullLines(currentSelection);
    if (lineSelection != currentSelection) {
      controller.selection = lineSelection;
      _onControllerChange();
    }
  }

  // --- NEW PRIVATE HELPER METHODS ---

  /// Expands the current selection to cover the full text of the lines it spans.
  CodeLineSelection _expandToFullLines(CodeLineSelection selection) {
    return CodeLineSelection(
      baseIndex: selection.start.index,
      baseOffset: 0,
      extentIndex: selection.end.index,
      extentOffset: controller.codeLines[selection.end.index].text.length,
    );
  }

  /// Finds the boundaries of the word at a given cursor position.
  CodeLineSelection? _findWordBoundaryAt(CodeLinePosition position) {
    final String line = controller.codeLines[position.index].text;
    if (position.offset >= line.length && line.isNotEmpty) {
      // Cursor is at the very end of the line, check character before
      if (line[position.offset - 1].trim().isEmpty) return null;
    } else if (line.isEmpty || line[position.offset].trim().isEmpty) {
      // Cursor is on whitespace
      return null;
    }

    int start = position.offset;
    int end = position.offset;

    // Find the start of the word by moving left
    while (start > 0 && line[start - 1].trim().isNotEmpty) {
      start--;
    }
    // Find the end of the word by moving right
    while (end < line.length && line[end].trim().isNotEmpty) {
      end++;
    }

    if (start == end) return null;

    return CodeLineSelection(
      baseIndex: position.index,
      baseOffset: start,
      extentIndex: position.index,
      extentOffset: end,
    );
  }

  /// Finds the next largest enclosing block (e.g., quotes, brackets) around a selection.
  CodeLineSelection? _findEnclosingBlock(CodeLineSelection selection) {
    final CodeLines codeLines = controller.codeLines;
    final Map<String, String> pairs = {'(': ')', '[': ']', '{': '}', "'": "'", '"': '"'};

    final CodeLinePosition startPos = selection.start;
    final CodeLinePosition endPos = selection.end;

    // Check for quote expansion on a single line
    if (startPos.index == endPos.index) {
      final line = codeLines[startPos.index].text;
      for (final quote in ["'", '"']) {
        final lastQuote = line.lastIndexOf(quote, startPos.offset);
        if (lastQuote != -1) {
          final nextQuote = line.indexOf(quote, endPos.offset);
          if (nextQuote != -1) {
            // CORRECTED: Use the default constructor with all four parameters.
            return CodeLineSelection(
              baseIndex: startPos.index,
              baseOffset: lastQuote,
              extentIndex: startPos.index,
              extentOffset: nextQuote + 1,
            );
          }
        }
      }
    }

    // Check for bracket expansion
    // Start searching from one character before the selection
    CodeLinePosition searchPos = startPos.offset > 0 
        ? CodeLinePosition(index: startPos.index, offset: startPos.offset - 1)
        : (startPos.index > 0 ? CodeLinePosition(index: startPos.index - 1, offset: codeLines[startPos.index - 1].text.length) : startPos);

    int scanLimit = 1000; // Safety break to prevent infinite loops
    int count = 0;

    while (count < scanLimit && (searchPos.index > 0 || searchPos.offset >= 0)) {
      final line = codeLines[searchPos.index].text;
      if (searchPos.offset >= line.length) {
          searchPos = CodeLinePosition(index: searchPos.index - 1, offset: codeLines[searchPos.index - 1].text.length - 1);
          continue;
      }
      final char = line[searchPos.offset];

      if (pairs.keys.contains(char)) {
        // We found an opening bracket. Find its match.
        final matchPos = _findMatchingBracket(codeLines, searchPos, pairs);
        if (matchPos != null) {
          // Check if this new block fully contains the original selection
          // CORRECTED: Use the named constructor CodeLineSelection.from()
          final blockSelection = CodeLineSelection.from(
            base: searchPos,
            extent: CodeLinePosition(index: matchPos.index, offset: matchPos.offset + 1)
          );
          if (blockSelection.contains(selection) && blockSelection != selection) {
            return blockSelection;
          }
        }
      }

      // Move to the previous character
      if (searchPos.offset > 0) {
        searchPos = CodeLinePosition(index: searchPos.index, offset: searchPos.offset - 1);
      } else if (searchPos.index > 0) {
        searchPos = CodeLinePosition(index: searchPos.index - 1, offset: codeLines[searchPos.index - 1].text.length);
      } else {
        break; // Reached start of document
      }
      count++;
    }

    return null; // No enclosing block found
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
    return {
      // The key 'content' will be used to identify this data during rehydration.
      'content': controller.text,
    };
  }
  
    // NEW METHOD: Centralizes updating the state provider.
  void _updateStateProvider() {
    ref.read(codeEditorStateProvider(widget.tab.id).notifier).update(
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
    }
  }
  
  // ... (bracket highlighting logic is unchanged) ...
  _BracketHighlightState _calculateBracketHighlights() {
    final selection = controller.selection;
    if (!selection.isCollapsed) {
      return const _BracketHighlightState();
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
    return _BracketHighlightState(
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
                backgroundColor: Colors.yellow.withOpacity(0.3),
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
  
    KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
        if (event is! RawKeyDownEvent) return KeyEventResult.ignored;
            final arrowKeyDirections = {
      LogicalKeyboardKey.arrowUp: AxisDirection.up,
      LogicalKeyboardKey.arrowDown: AxisDirection.down,
      LogicalKeyboardKey.arrowLeft: AxisDirection.left,
      LogicalKeyboardKey.arrowRight: AxisDirection.right,
    };
        final direction = arrowKeyDirections[event.logicalKey];
        final shiftPressed = event.isShiftPressed;
        
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
    ref.listen(
      tabMetadataProvider.select((m) => m[widget.tab.id]?.file.uri),
      (previous, next) {
        if (previous != next && next != null) {
          setState(() {
            _languageKey = CodeThemes.inferLanguageKey(next);
            _commentFormatter = CodeEditorLogic.getCommentFormatter(next);
          });
        }
      },
    );

    final codeEditorSettings = ref.watch(
      settingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    );
    final selectedThemeName = codeEditorSettings?.themeName ?? 'Atom One Dark';

    // --- THIS IS THE MODIFIED SECTION ---
    return Focus(
        focusNode: _focusNode,
        onKey: _handleKeyEvent,
        autofocus: true,
        child: CodeEditor(
          controller: controller,
          findController: findController,
          findBuilder: (context, controller, readOnly) {
            return CodeFindPanelView(
              controller: controller,
              readOnly: readOnly,
            );
          },
          commentFormatter: _commentFormatter,
          
          // REMOVED: The scrollbarBuilder is no longer needed because
          // the ScrollBehavior is now handling scrollbar creation for us.
          // scrollbarBuilder: (context, child, details) { ... },
          
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
              bracketHighlightState: _bracketHighlightState,
            );
          },
          style: CodeEditorStyle(
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
  final _BracketHighlightState bracketHighlightState;

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

class CodeEditorSelectionAppBar extends ConsumerWidget {
  final Command cutCommand;
  final Command copyCommand;
  final Command pasteCommand;
  final Command commentCommand;       // <-- ADDED
  final Command moveLineUpCommand;    // <-- ADDED
  final Command moveLineDownCommand;  // <-- ADDED

  const CodeEditorSelectionAppBar({
    super.key,
    required this.cutCommand,
    required this.copyCommand,
    required this.pasteCommand,
    required this.commentCommand,      // <-- ADDED
    required this.moveLineUpCommand,   // <-- ADDED
    required this.moveLineDownCommand, // <-- ADDED
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // WRAPPED in CodeEditorTapRegion
    return CodeEditorTapRegion(
      child: Material(
        elevation: 4.0,
        color: Theme.of(context).appBarTheme.backgroundColor,
        child: SafeArea(
          child: Container(
            height: kToolbarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              // The contextual commands.
              children: [
                // Use a Spacer to push the other commands to the right
                const Spacer(), 
                CommandButton(command: commentCommand),
                CommandButton(command: moveLineUpCommand),
                CommandButton(command: moveLineDownCommand),
                const VerticalDivider(indent: 12, endIndent: 12), // Visual separator
                CommandButton(command: cutCommand),
                CommandButton(command: copyCommand),
                CommandButton(command: pasteCommand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}