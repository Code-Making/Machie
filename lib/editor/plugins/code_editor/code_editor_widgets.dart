// lib/plugins/code_editor/code_editor_widgets.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import '../../../app/app_notifier.dart';
import '../../../editor/services/editor_service.dart';
import '../../../settings/settings_notifier.dart';
import 'code_themes.dart';
import 'code_editor_models.dart';
import '../../tab_state_manager.dart';

// --- NEW LOCAL STATE PROVIDERS ---

/// Holds the CodeEditingController for the currently active code editor tab.
/// The widget itself is responsible for setting and clearing this.
final activeCodeControllerProvider =
    StateProvider.autoDispose<CodeLineEditingController?>((ref) => null);

/// Holds the ephemeral "mark" position for the active editor.
final codeEditorMarkPositionProvider =
    StateProvider.autoDispose<CodeLinePosition?>((ref) => null);

/// Holds the bracket highlighting state for the active editor.
final bracketHighlightProvider =
    StateProvider.autoDispose<BracketHighlightState>((ref) {
  return const BracketHighlightState();
});

// Providers for undo/redo state, read by the command buttons.
final canUndoProvider = StateProvider.autoDispose<bool>((ref) => false);
final canRedoProvider = StateProvider.autoDispose<bool>((ref) => false);

/// A helper class to hold bracket highlighting data.
class BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final Set<int> highlightedLines;
  const BracketHighlightState({
    this.bracketPositions = const {},
    this.highlightedLines = const {},
  });
}

// --- WIDGET IMPLEMENTATION ---

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeEditorTab tab;
  final String initialContent;
  final CodeCommentFormatter? commentFormatter;
  final CodeIndicatorBuilder? indicatorBuilder;

  const CodeEditorMachine({
    super.key,
    required this.tab,
    required this.initialContent,
    this.commentFormatter,
    this.indicatorBuilder,
  });

  @override
  ConsumerState<CodeEditorMachine> createState() => _CodeEditorMachineState();
}

class _CodeEditorMachineState extends ConsumerState<CodeEditorMachine> {
  late final CodeLineEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    
    // The widget now creates and owns its controller.
    _controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(widget.initialContent),
      spanBuilder: _buildHighlightingSpan,
    );

    // Set this controller as the active one for commands to use.
    // Use a post-frame callback to ensure providers are available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(activeCodeControllerProvider.notifier).state = _controller;
      }
    });

    _controller.addListener(_onControllerChange);
    // Initial update
    _onControllerChange();
  }

  @override
  void dispose() {
    // Clean up the controller and its listeners.
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    _focusNode.dispose();
    
    // Clear the active controller provider if this instance was the active one.
    if (ref.read(activeCodeControllerProvider) == _controller) {
      ref.read(activeCodeControllerProvider.notifier).state = null;
    }
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    
    // Update global state via the service facade.
    ref.read(editorServiceProvider).markCurrentTabDirty();
    
    // Update local providers for UI elements.
    ref.read(canUndoProvider.notifier).state = _controller.canUndo;
    ref.read(canRedoProvider.notifier).state = _controller.canRedo;
    ref.read(bracketHighlightProvider.notifier).state = _calculateBracketHighlights();
  }

  BracketHighlightState _calculateBracketHighlights() {
    final selection = _controller.selection;
    if (!selection.isCollapsed) {
      return const BracketHighlightState();
    }
    // ... (logic from the old plugin is now here) ...
    final position = selection.base;
    final brackets = {'(': ')', '[': ']', '{': '}'};
    final line = _controller.codeLines[position.index].text;
    Set<CodeLinePosition> newPositions = {};
    Set<int> newHighlightedLines = {};
    for (int offset in [position.offset, position.offset - 1]) {
      if (offset >= 0 && offset < line.length) {
        final char = line[offset];
        if (brackets.keys.contains(char) || brackets.values.contains(char)) {
          final currentPosition = CodeLinePosition(index: position.index, offset: offset);
          final matchPosition = _findMatchingBracket(_controller.codeLines, currentPosition, brackets);
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
  
  CodeLinePosition? _findMatchingBracket(CodeLines codeLines, CodeLinePosition position, Map<String, String> brackets) {
    // ... (logic from the old plugin is now here) ...
  }

  TextSpan _buildHighlightingSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final highlightState = ref.read(bracketHighlightProvider);
    // ... (rest of highlighting logic, unchanged) ...
  }

  @override
  Widget build(BuildContext context) {
    final codeEditorSettings = ref.watch(settingsProvider.select((s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?));
    final currentLanguageKey = widget.tab.languageKey;
    final selectedThemeName = codeEditorSettings?.themeName ?? 'Atom One Dark';

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: CodeEditor(
        controller: _controller,
        commentFormatter: widget.commentFormatter,
        indicatorBuilder: widget.indicatorBuilder,
        style: CodeEditorStyle(
          fontSize: codeEditorSettings?.fontSize ?? 12.0,
          fontFamily: codeEditorSettings?.fontFamily ?? 'JetBrainsMono',
          codeTheme: CodeHighlightTheme(
            theme: CodeThemes.availableCodeThemes[selectedThemeName] ?? CodeThemes.availableCodeThemes['Atom One Dark']!,
            languages: CodeThemes.getHighlightThemeMode(currentLanguageKey),
          ),
        ),
        wordWrap: codeEditorSettings?.wordWrap ?? false,
      ),
    );
  }
}

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
    // The indicator now watches the simple local provider.
    final highlightedLines = ref.watch(bracketHighlightProvider.select((s) => s.highlightedLines));

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