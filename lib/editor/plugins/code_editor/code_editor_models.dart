// lib/editor/plugins/code_editor/code_editor_models.dart
import 'package:flutter/material.dart'; // NEW IMPORT for GlobalKey
import 'package:re_editor/re_editor.dart';
import '../plugin_models.dart';
import '../../editor_tab_models.dart';
import '../../../data/file_handler/file_handler.dart';

@immutable
class CodeEditorTab extends EditorTab {
  final CodeCommentFormatter commentFormatter;
  final String? languageKey;
  final String initialContent;

  // NEW: A key to uniquely identify the state of the editor widget instance.
  final GlobalKey<_CodeEditorMachineState> editorKey;

  CodeEditorTab({
    required super.file,
    required super.plugin,
    required this.commentFormatter,
    this.languageKey,
    required this.initialContent,
  }) : editorKey = GlobalKey<_CodeEditorMachineState>(); // Key is created with the tab

  @override
  void dispose() {}

  @override
  CodeEditorTab copyWith({
    DocumentFile? file,
    EditorPlugin? plugin,
    CodeCommentFormatter? commentFormatter,
    String? languageKey,
    String? initialContent,
  }) {
    // Note: We don't copy the key. The new tab instance gets a new key.
    // This is fine because the widget it's attached to will also be new.
    return CodeEditorTab(
      file: file ?? this.file,
      plugin: plugin ?? this.plugin,
      commentFormatter: commentFormatter ?? this.commentFormatter,
      languageKey: languageKey ?? this.languageKey,
      initialContent: initialContent ?? this.initialContent,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'code',
    'fileUri': file.uri,
    'pluginType': plugin.runtimeType.toString(),
    'languageKey': languageKey,
  };
}

// ... CodeEditorSettings is unchanged ...