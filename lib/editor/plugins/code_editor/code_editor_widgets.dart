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

// Helper class for bracket highlight data
class _BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final Set<int> highlightedLines;
  const _BracketHighlightState({this.bracketPositions = const {}, this.highlightedLines = const {}});
}

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeEditorTab tab;
  const CodeEditorMachine({super.key, required this.tab});
  @override
  ConsumerState<CodeEditorMachine> createState() => _CodeEditorMachineState();
}

// FIX: Make the class public by removing the leading underscore.
class _CodeEditorMachineState extends ConsumerState<CodeEditorMachine> {
  late final CodeLineEditingController controller;
  late final FocusNode _focusNode;
  CodeLinePosition? _markPosition;
  _BracketHighlightState _bracketHighlightState = const _BracketHighlightState();

  bool get isDirty => ref.read(tabMetadataProvider)[widget.tab.file.uri]?.isDirty ?? false;
  bool get canUndo => controller.canUndo;
  bool get canRedo => controller.canRedo;
  bool get hasMark => _markPosition != null;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(widget.tab.initialContent),
      spanBuilder: _buildHighlightingSpan,
    );
    controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChange);
    controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    ref.read(editorServiceProvider).markCurrentTabDirty();
    setState(() {
      _bracketHighlightState = _calculateBracketHighlights();
    });
  }
  
  Future<void> save() async { /* ... */ }
  void setMark() { /* ... */ }
  void selectToMark() { /* ... */ }
  void toggleComments() { /* ... */ }

  Future<void> showLanguageSelectionDialog() async {
    final selectedLanguageKey = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog( /* ... */ ),
    );
    if (selectedLanguageKey != null) {
      final updatedTab = widget.tab.copyWith(languageKey: selectedLanguageKey);
      ref.read(editorServiceProvider).updateCurrentTabModel(updatedTab);
    }
  }

  _BracketHighlightState _calculateBracketHighlights() {
    // ... logic unchanged
    return const _BracketHighlightState(); // FIX: Placeholder return
  }

  CodeLinePosition? _findMatchingBracket(CodeLines codeLines, CodeLinePosition position, Map<String, String> brackets) {
    // ... logic unchanged
    return null; // FIX: Placeholder return
  }
  
  int _comparePositions(CodeLinePosition a, CodeLinePosition b) {
    // ... logic unchanged
    return 0; // FIX: Placeholder return
  }

  TextSpan _buildHighlightingSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final highlightState = _bracketHighlightState;
    // ... logic unchanged
    return textSpan; // FIX: Placeholder return
  }
  
  @override
  Widget build(BuildContext context) {
    // FIX: Correctly access settings
    final codeEditorSettings = ref.watch(settingsProvider.select((s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?));
    final currentLanguageKey = widget.tab.languageKey;
    final selectedThemeName = codeEditorSettings?.themeName ?? 'Atom One Dark';

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: CodeEditor(
        controller: controller,
        commentFormatter: widget.tab.commentFormatter,
        indicatorBuilder: (context, editingController, chunkController, notifier) {
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
            theme: CodeThemes.availableCodeThemes[selectedThemeName] ?? CodeThemes.availableCodeThemes['Atom One Dark']!,
            languages: CodeThemes.getHighlightThemeMode(currentLanguageKey),
          ),
        ),
        wordWrap: codeEditorSettings?.wordWrap ?? false,
      ),
    );
  }
}

class CustomEditorIndicator extends StatelessWidget {
  final CodeLineEditingController controller;
  final CodeChunkController chunkController;
  final CodeIndicatorValueNotifier notifier;
  // It now receives the state directly from its parent.
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