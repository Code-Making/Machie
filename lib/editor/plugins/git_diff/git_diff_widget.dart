// =========================================
// UPDATED: lib/editor/plugins/git_diff/git_diff_widget.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/styles/github.dart'; 

import '../../../data/dto/tab_hot_state_dto.dart';
import '../../editor_tab_models.dart';
import 'git_diff_models.dart';
import 'git_diff_indicator.dart'; 

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

  final Color colorAddition = const Color(0xFFDDFFDD);
  final Color colorDeletion = const Color(0xFFFFDDDD);
  final Color colorHunk = const Color(0xFFF1F8FF);

  @override
  void initState() {
    super.initState();
    // <<< FIX: Use the '.fromText()' factory constructor.
    _controller = CodeLineEditingController.fromText(
      widget.tab.diffContent,
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
  void syncCommandContext() {}
  @override
  Future<EditorContent> getContent() async => EditorContentString(widget.tab.diffContent);
  @override
  void onSaveSuccess(String newHash) {}
  @override
  void redo() {}
  @override
  void undo() {}
  @override
  Future<TabHotStateDto?> serializeHotState() async => null;

  // --- WIDGET BUILD ---
  
  // ... The rest of the file is unchanged ...
  @override
  Widget build(BuildContext context) {
    return CodeEditor(
      controller: _controller,
      readOnly: true,
      style: CodeEditorStyle(
        codeTheme: CodeHighlightTheme(
          languages: {'diff': CodeHighlightThemeMode(mode: langDiff)},
          theme: githubTheme,
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        fontSize: 13,
      ),
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
      chunkAnalyzer: const GitDiffChunkAnalyzer(),
    );
  }

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

    if (backgroundColor == null) {
      return textSpan;
    }

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

class GitDiffChunkAnalyzer implements CodeChunkAnalyzer {
  const GitDiffChunkAnalyzer();

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    final List<CodeChunk> chunks = [];
    int? hunkStartIndex;

    for (int i = 0; i < codeLines.length; i++) {
      if (codeLines[i].text.startsWith('@@')) {
        if (hunkStartIndex != null) {
          if (i > hunkStartIndex + 1) {
            chunks.add(CodeChunk(hunkStartIndex, i));
          }
        }
        hunkStartIndex = i;
      }
    }

    if (hunkStartIndex != null && codeLines.length > hunkStartIndex + 1) {
      chunks.add(CodeChunk(hunkStartIndex, codeLines.length));
    }

    return chunks;
  }
}