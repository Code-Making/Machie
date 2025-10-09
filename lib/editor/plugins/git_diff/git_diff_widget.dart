// =========================================
// NEW FILE: lib/editor/plugins/git_diff/git_diff_widget.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/styles/github.dart'; // A nice, clean theme for diffs

import '../../../data/dto/tab_hot_state_dto.dart';
import '../../editor_tab_models.dart';
import 'git_diff_models.dart';
import 'git_diff_indicator.dart'; // We will create this next

class GitDiffEditorWidget extends EditorWidget {
  @override
  final GitDiffTab tab;
  
  const GitDiffEditorWidget({
    required GlobalKey<GitDiffEditorWidgetState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  GitDiffEditorWidgetState createState() => GitDiffEditorWidgetState();
}

class GitDiffEditorWidgetState extends EditorWidgetState<GitDiffEditorWidget> {
  late final CodeLineEditingController _controller;

  // Define colors for the view
  final Color colorAddition = const Color(0xFFDDFFDD);
  final Color colorDeletion = const Color(0xFFFFDDDD);
  final Color colorHunk = const Color(0xFFF1F8FF);

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController(
      text: widget.tab.diffContent,
      // The spanBuilder is the key to line-based background colors.
      spanBuilder: _buildDiffTextSpan,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // --- EditorWidgetState Contract (Read-Only Implementation) ---

  @override
  void syncCommandContext() {
    // No context to sync for a read-only viewer
  }

  @override
  Future<EditorContent> getContent() async => EditorContentString(widget.tab.diffContent);

  @override
  void onSaveSuccess(String newHash) {
    // No-op
  }

  @override
  void redo() {
    // No-op
  }

  @override
  void undo() {
    // No-op
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async => null;


  // --- WIDGET BUILD ---
  @override
  Widget build(BuildContext context) {
    return CodeEditor(
      controller: _controller,
      readOnly: true, // This is a viewer, not an editor.
      style: CodeEditorStyle(
        // Use the 'diff' language for syntax highlighting.
        codeTheme: CodeHighlightTheme(
          languages: {'diff': CodeHighlightThemeMode(mode: langDiff)},
          theme: githubTheme,
        ),
        // A neutral background works best.
        backgroundColor: Theme.of(context).colorScheme.surface,
        fontSize: 13,
      ),
      // Use our custom indicator for the gutter.
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return GitDiffIndicator(
          controller: editingController,
          notifier: notifier,
          style: CodeEditorStyle(
            textColor: Colors.grey.shade600,
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            fontSize: 12,
          ),
        );
      },
      // Use a custom chunk analyzer for folding hunks.
      chunkAnalyzer: const GitDiffChunkAnalyzer(),
    );
  }

  /// This builder intercepts the rendering of each line's TextSpan.
  /// We wrap it in a new span that provides the appropriate background color.
  TextSpan _buildDiffTextSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final String text = codeLine.text;
    Color? backgroundColor;

    if (text.startsWith('+') && !text.startsWith('+++')) {
      backgroundColor = colorAddition;
    } else if (text.startsWith('-') && !text.startsWith('---')) {
      backgroundColor = colorDeletion;
    } else if (text.startsWith('@@')) {
      backgroundColor = colorHunk;
    }

    // If it's a normal context line, return the original span.
    if (backgroundColor == null) {
      return textSpan;
    }

    // Otherwise, wrap the original span to apply the background.
    return TextSpan(
      style: style.copyWith(
        backgroundColor: backgroundColor,
      ),
      children: [
        textSpan,
      ],
    );
  }
}

/// A custom chunk analyzer that identifies foldable regions based on diff hunks.
class GitDiffChunkAnalyzer implements CodeChunkAnalyzer {
  const GitDiffChunkAnalyzer();

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    final List<CodeChunk> chunks = [];
    int? hunkStartIndex;

    for (int i = 0; i < codeLines.length; i++) {
      if (codeLines[i].text.startsWith('@@')) {
        // The start of a new hunk marks the end of the previous one.
        if (hunkStartIndex != null) {
          // Only create a chunk if it has content to fold.
          if (i > hunkStartIndex + 1) {
            chunks.add(CodeChunk(hunkStartIndex, i));
          }
        }
        // Start tracking the new hunk.
        hunkStartIndex = i;
      }
    }

    // Add the final hunk if it exists.
    if (hunkStartIndex != null && codeLines.length > hunkStartIndex + 1) {
      chunks.add(CodeChunk(hunkStartIndex, codeLines.length));
    }

    return chunks;
  }
}