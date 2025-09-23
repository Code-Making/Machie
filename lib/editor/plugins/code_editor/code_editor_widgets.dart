// =========================================
// FILE: lib/editor/plugins/code_editor/code_editor_widgets.dart
// =========================================

// lib/plugins/code_editor/code_editor_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import '../../../editor/services/editor_service.dart';
import '../../../settings/settings_notifier.dart';
import 'code_themes.dart';
import 'code_editor_models.dart';
import 'code_editor_logic.dart';
import '../../tab_state_manager.dart';
import '../../../app/app_notifier.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'code_editor_state.dart'; // <-- ADD THIS IMPORT

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

  CodeLinePosition? _markPosition;
  _BracketHighlightState _bracketHighlightState =
      const _BracketHighlightState();

  late CodeCommentFormatter _commentFormatter;
  late String? _languageKey;

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
    controller.addListener(_onControllerChange);
    controller.dirty.addListener(_onDirtyStateChange); // <-- NEW LISTENER
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

  @override
  void dispose() {
    // Make sure to remove the new listener.
    controller.dirty.removeListener(_onDirtyStateChange); // <-- REMOVE LISTENER
    controller.removeListener(_onControllerChange);
    controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --- LOGIC AND METHODS ---
  
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
    
    // REMOVED: No longer need to manually mark as dirty here.
    // The controller.dirty listener will handle it automatically.
    // ref.read(editorServiceProvider).markCurrentTabDirty(); 

    // This is still needed for things that aren't the dirty flag,
    // like bracket highlighting and undo/redo status.
    setState(() {
      _bracketHighlightState = _calculateBracketHighlights();
    });

    // The logic to update the Undo/Redo/Mark status for commands is still valid.
    _updateStateProvider(); 
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
    // Use the tab's stable ID to get the correct notifier instance.
    ref.read(codeEditorStateProvider(widget.tab.id).notifier).update(
          canUndo: controller.canUndo,
          canRedo: controller.canRedo,
          hasMark: _markPosition != null,
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
    // This listener ensures that if the file is renamed, the widget will rebuild
    // with the correct syntax highlighting.
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

    return Focus(
      focusNode: _focusNode,
      onKey: _handleKeyEvent,
      autofocus: true,
      child: CodeEditor(
        controller: controller,
        commentFormatter: _commentFormatter,
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