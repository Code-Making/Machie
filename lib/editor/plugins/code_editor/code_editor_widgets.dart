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

// Helper class for bracket highlight data
class _BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final Set<int> highlightedLines;
  const _BracketHighlightState({this.bracketPositions = const {}, this.highlightedLines = const {}});
}

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeEditorTab tab;

  const CodeEditorMachine({
    // The key is now the GlobalKey from the tab model, passed from the plugin.
    super.key,
    required this.tab,
  });

  @override
  // The State class is now public to be accessible via the GlobalKey.
  CodeEditorMachineState createState() => CodeEditorMachineState();
}

class CodeEditorMachineState extends ConsumerState<CodeEditorMachine> {
  // --- STATE ---
  // The widget's State object is now the single source of truth for "hot" state.
  late final CodeLineEditingController controller;
  late final FocusNode _focusNode;
  
  CodeLinePosition? _markPosition;
  _BracketHighlightState _bracketHighlightState = const _BracketHighlightState();
 
 late CodeCommentFormatter _commentFormatter;
 late String? _languageKey;

  // --- PUBLIC PROPERTIES (for the command system) ---
  bool get isDirty => ref.read(tabMetadataProvider)[widget.tab.file.uri]?.isDirty ?? false;
  bool get canUndo => controller.canUndo;
  bool get canRedo => controller.canRedo;
  bool get hasMark => _markPosition != null;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    
    // Initialize the internal state from the tab's file URI.
    _languageKey = CodeThemes.inferLanguageKey(widget.tab.file.uri);
    _commentFormatter = CodeEditorLogic.getCommentFormatter(widget.tab.file.uri);

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
    
    // Update global metadata via the service facade. This keeps the
    // UI outside this widget (like the tab bar) in sync.
    ref.read(editorServiceProvider).markCurrentTabDirty();
    
    // Update local state and trigger a rebuild of this widget if necessary.
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
      builder: (ctx) => AlertDialog(
          title: const Text('Select Language'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: CodeThemes.languageNameToModeMap.keys.length,
              itemBuilder: (context, index) {
                final langKey = CodeThemes.languageNameToModeMap.keys.elementAt(
                  index,
                );
                return ListTile(
                  title: Text(CodeThemes.formatLanguageName(langKey)),
                  onTap: () => Navigator.pop(ctx, langKey),
                );
              },
            ),
          ),
        ),
    );
    if (selectedLanguageKey != null) {
      final updatedTab = widget.tab.copyWith(languageKey: selectedLanguageKey);
      ref.read(editorServiceProvider).updateCurrentTabModel(updatedTab);
      setState(() {
        _languageKey = selectedLanguageKey;
      });
    }
  }

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
          final currentPosition = CodeLinePosition(index: position.index, offset: offset);
          final matchPosition = _findMatchingBracket(controller.codeLines, currentPosition, brackets);
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
  
  CodeLinePosition? _findMatchingBracket(CodeLines codeLines, CodeLinePosition position, Map<String, String> brackets) {
    final line = codeLines[position.index].text;
    final char = line[position.offset];
    final isOpen = brackets.keys.contains(char);
    final target = isOpen ? brackets[char] : brackets.keys.firstWhere((k) => brackets[k] == char, orElse: () => '');
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
            builtSpans.add(TextSpan(text: text.substring(lastSplit, i), style: spanStyle));
          }
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
      if (lastSplit < text.length) {
        builtSpans.add(TextSpan(text: text.substring(lastSplit), style: spanStyle));
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
  
  @override
  Widget build(BuildContext context) {
    final codeEditorSettings = ref.watch(settingsProvider.select((s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?));
    final selectedThemeName = codeEditorSettings?.themeName ?? 'Atom One Dark';

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: CodeEditor(
        controller: controller,
        commentFormatter: _commentFormatter,
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
            languages: CodeThemes.getHighlightThemeMode(_languageKey),
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
  // It now receives the state directly from its parent widget.
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