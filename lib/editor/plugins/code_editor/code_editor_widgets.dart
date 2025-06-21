// lib/plugins/code_editor/code_editor_widgets.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../../app/app_notifier.dart';
import '../../../settings/settings_notifier.dart';
import 'code_themes.dart';
import 'code_editor_models.dart';
import 'code_editor_plugin.dart';
import '../../tab_state_manager.dart'; // REFACTOR: Import manager

final canUndoProvider = StateProvider<bool>((ref) => false);
final canRedoProvider = StateProvider<bool>((ref) => false);

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeEditorTab tab;
  final CodeLineEditingController controller;
  final CodeCommentFormatter? commentFormatter;
  final CodeIndicatorBuilder? indicatorBuilder;

  const CodeEditorMachine({
    super.key,
    required this.tab,
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
    if (!mounted) return;
    ref.read(canUndoProvider.notifier).state = widget.controller.canUndo;
    ref.read(canRedoProvider.notifier).state = widget.controller.canRedo;
    (widget.tab.plugin as CodeEditorPlugin).handleBracketHighlight(ref, widget.tab);
    setState(() {});
  }

  void _handleControllerChange() {
    if (!mounted) return;
    ref.read(appNotifierProvider.notifier).markCurrentTabDirty();
    _updateAllStatesFromController();
  }
  
  void _addControllerListeners(CodeLineEditingController controller) {
    controller.addListener(_handleControllerChange);
  }
  void _removeControllerListeners(CodeLineEditingController controller) {
    controller.removeListener(_handleControllerChange);
  }
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final direction = _arrowKeyDirections[event.logicalKey];
    if (direction != null) {
      HardwareKeyboard.instance.isShiftPressed
          ? widget.controller.extendSelection(direction)
          : widget.controller.moveCursor(direction);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              widget.controller.makeCursorVisible();
            }
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final codeEditorSettings = ref.watch(settingsProvider.select((s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?));
    final currentLanguageKey = ref.watch(appNotifierProvider.select((s) {
      final tab = s.value?.currentProject?.session.currentTab;
      return (tab is CodeEditorTab) ? tab.languageKey : null;
    }));
    final selectedThemeName = codeEditorSettings?.themeName ?? 'Atom One Dark';

    return Focus(
      autofocus: true,
      onFocusChange: (bool focus) => _handleFocusChange(),
      onKeyEvent: (n, e) => _handleKeyEvent(n, e),
      child: CodeEditor(
        controller: widget.controller,
        commentFormatter: widget.commentFormatter,
        indicatorBuilder: widget.indicatorBuilder,
        style: CodeEditorStyle(
          fontSize: codeEditorSettings?.fontSize ?? 12,
          fontFamily: codeEditorSettings?.fontFamily ?? 'JetBrainsMono',
          codeTheme: CodeHighlightTheme(
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

class CustomEditorIndicator extends ConsumerWidget {
  final CodeLineEditingController controller;
  final CodeChunkController chunkController;
  final CodeIndicatorValueNotifier notifier;
  final CodeEditorTab tab;

  const CustomEditorIndicator({
    super.key,
    required this.controller,
    required this.chunkController,
    required this.notifier,
    required this.tab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REFACTOR: Fix the cast and get state correctly.
    final plugin = tab.plugin as CodeEditorPlugin;
    final tabState = plugin.getTabState(ref, tab);
    final highlightedLines = tabState?.bracketHighlightState.highlightedLines ?? const {};

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Row(
        children: [
          _CustomLineNumberWidget(
            controller: controller,
            notifier: notifier,
            highlightedLines: highlightedLines,
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

// REFACTOR: This function now correctly builds the span for a line.
TextSpan buildHighlightingSpan({
  required BuildContext context,
  required CodeEditorTab tab,
  required CodeLine codeLine,
  required TextStyle style,
}) {
  // Get the state from the tab itself via the plugin
  final plugin = tab.plugin as CodeEditorPlugin;
  final container = ProviderScope.containerOf(context);
  final tabState = container.read(tabStateManagerProvider.notifier).getState<CodeEditorTabState>(tab.file.uri);
  
  if (tabState == null) {
    return TextSpan(text: codeLine.text, style: style);
  }

  final highlightState = tabState.bracketHighlightState;
  final lineIndex = tabState.controller.codeLines.indexOf(codeLine);
  if (lineIndex == -1) {
     return TextSpan(text: codeLine.text, style: style);
  }
  
  final highlightPositions =
      highlightState.bracketPositions
          .where((pos) => pos.index == lineIndex)
          .map((pos) => pos.offset)
          .toSet();

  // If there's nothing to highlight on this line, return the pre-styled spans from syntax highlighting
  if (highlightPositions.isEmpty) {
    return TextSpan(children: codeLine.spans, style: style);
  }

  // If there are highlights, we need to rebuild the spans for this line
  final builtSpans = <TextSpan>[];
  int currentPosition = 0;
  
  // The source of truth is the syntax-highlighted spans in codeLine.spans
  final sourceSpans = codeLine.spans.isNotEmpty ? codeLine.spans : [TextSpan(text: codeLine.text)];

  for (final span in sourceSpans) {
    final text = span.text ?? '';
    final spanStyle = span.style ?? style;
    int lastSplit = 0;
    
    for (int i = 0; i < text.length; i++) {
      final absolutePosition = currentPosition + i;
      if (highlightPositions.contains(absolutePosition)) {
        // Add text before the highlight
        if (i > lastSplit) {
          builtSpans.add(TextSpan(text: text.substring(lastSplit, i), style: spanStyle));
        }
        // Add the highlighted character
        builtSpans.add(TextSpan(
          text: text[i],
          style: spanStyle.copyWith(
            backgroundColor: Colors.yellow.withOpacity(0.3),
            fontWeight: FontWeight.bold,
          ),
        ));
        lastSplit = i + 1;
      }
    }
    // Add any remaining text after the last highlight
    if (lastSplit < text.length) {
      builtSpans.add(TextSpan(text: text.substring(lastSplit), style: spanStyle));
    }
    currentPosition += text.length;
  }
  
  return TextSpan(children: builtSpans, style: style);
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