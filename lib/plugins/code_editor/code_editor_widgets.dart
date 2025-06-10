import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../app/app_notifier.dart';
import '../../settings/settings_notifier.dart';
import 'code_themes.dart';
import 'code_editor_models.dart';

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
    controller.removeListener(_handleControllerChange);
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

  void _handleFocusChange() {
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
    final currentLanguageKey = ref.watch(
      appNotifierProvider.select((s) {
        final tab = s.value?.currentProject?.session.currentTab;
        return (tab is CodeEditorTab) ? tab.languageKey : null;
      }),
    );

    // Get the selected theme name from settings
    final selectedThemeName =
        codeEditorSettings?.themeName ?? 'Atom One Dark'; // Default theme

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
            theme:
                CodeThemes.availableCodeThemes[selectedThemeName] ??
                CodeThemes.availableCodeThemes['Atom One Dark']!,
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
    final currentTab =
        ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (currentTab is! CodeEditorTab) {
      state = BracketHighlightState();
      return;
    }
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

class CustomEditorIndicator extends ConsumerWidget {
  final CodeLineEditingController controller;
  final CodeChunkController chunkController;
  final CodeIndicatorValueNotifier notifier;

  const CustomEditorIndicator({
    super.key,
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
