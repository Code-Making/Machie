import 'package:collection/collection.dart';
import 'package:re_editor/re_editor.dart';
import 'package:flutter/material.dart';

import '../plugin_models.dart';
import '../../session/session_models.dart';
import '../../data/file_handler/file_handler.dart';

@immutable
class CodeEditorTab extends EditorTab {
  final CodeLineEditingController controller;
  final CodeCommentFormatter commentFormatter;
  final String? languageKey;

  const CodeEditorTab({
    required super.file,
    required this.controller,
    required super.plugin,
    required this.commentFormatter,
    super.isDirty = false,
    this.languageKey,
  });

  @override
  void dispose() => controller.dispose();
  @override
  String get contentString => controller.text;

  @override
  CodeEditorTab copyWith({
    DocumentFile? file,
    EditorPlugin? plugin,
    bool? isDirty,
    CodeLineEditingController? controller,
    CodeCommentFormatter? commentFormatter,
    String? languageKey,
  }) {
    return CodeEditorTab(
      file: file ?? this.file,
      plugin: plugin ?? this.plugin,
      isDirty: isDirty ?? this.isDirty,
      controller: controller ?? this.controller,
      commentFormatter: commentFormatter ?? this.commentFormatter,
      languageKey: languageKey ?? this.languageKey,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'code',
        'fileUri': file.uri,
        'pluginType': plugin.runtimeType.toString(),
        'languageKey': languageKey,
        'isDirty': isDirty,
      };
}