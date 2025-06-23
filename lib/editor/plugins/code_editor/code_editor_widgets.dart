// lib/plugins/code_editor/code_editor_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import '../../../app/app_notifier.dart';
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
  const _BracketHighlightState({
    this.bracketPositions = const {},
    this.highlightedLines = const {},
  });
}

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeEditorTab tab;

  const CodeEditorMachine({
    // The key is now passed from the plugin's buildEditor method
    super.key,
    required this.tab,
  });

  @override
  ConsumerState<CodeEditorMachine> createState() => _CodeEditorMachineState();
}

// The State class is now public so the GlobalKey can reference its type.
class _CodeEditorMachineState extends ConsumerState<CodeEditorMachine> {
  // --- STATE ---
  late final CodeLineEditingController controller;
  late final FocusNode _focusNode;
  
  // All "hot" state is now here, inside the widget's State object.
  CodeLinePosition? _markPosition;
  _BracketHighlightState _bracketHighlightState = const _BracketHighlightState();

  // --- PROPERTIES ---
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

  // --- LOGIC AND METHODS (moved from plugin) ---

  void _onControllerChange() {
    if (!mounted) return;
    
    // Update global metadata via the service facade
    ref.read(editorServiceProvider).markCurrentTabDirty();
    
    // Update local state and trigger a rebuild if necessary
    setState(() {
      _bracketHighlightState = _calculateBracketHighlights();
    });
  }
  
  Future<void> save() async {
    final project = ref.read(appNotifierProvider).value!.currentProject!;
    await ref.read(editorServiceProvider).saveCurrentTab(project, content: controller.text);
  }

  void setMark() {
    setState(() {
      _markPosition = controller.selection.base;
    });
  }
  
  void selectToMark() {
    if (_markPosition == null) return;
    final currentPosition = controller.selection.base;
    final start = _comparePositions(_markPosition!, currentPosition) < 0 ? _markPosition! : currentPosition;
    final end = _comparePositions(_markPosition!, currentPosition) < 0 ? currentPosition : _markPosition!;
    controller.selection = CodeLineSelection(
      baseIndex: start.index,
      baseOffset: start.offset,
      extentIndex: end.index,
      extentOffset: end.offset,
    );
  }
  
  void toggleComments() {
    final formatted = widget.tab.commentFormatter.format(
      controller.value,
      controller.options.indent,
      true,
    );
    controller.runRevocableOp(() => controller.value = formatted);
  }
  
  Future<void> showLanguageSelectionDialog() async {
    final selectedLanguageKey = await showDialog<String>(
      context: context,
      builder: (ctx) { /* ... dialog UI ... */ },
    );
    if (selectedLanguageKey != null) {
      final updatedTab = widget.tab.copyWith(languageKey: selectedLanguageKey);
      ref.read(editorServiceProvider).updateCurrentTabModel(updatedTab);
    }
  }

  _BracketHighlightState _calculateBracketHighlights() {
    // ... (logic is identical to before)
  }

  CodeLinePosition? _findMatchingBracket(CodeLines codeLines, CodeLinePosition position, Map<String, String> brackets) {
    // ... (logic is identical to before)
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
    // Highlighting logic now reads from the local state variable
    final highlightState = _bracketHighlightState;
    // ... (rest of highlighting logic is unchanged)
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