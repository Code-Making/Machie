// lib/session/session_models.dart
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../project/file_handler/file_handler.dart'; // For DocumentFile
import '../plugins/plugin_architecture.dart';
import '../project/project_models.dart';

// Represents the state of an editing session within a single project.
@immutable
class SessionState {
  final List<EditorTab> tabs;
  final int currentTabIndex;

  const SessionState({
    this.tabs = const [],
    this.currentTabIndex = 0,
  });

  EditorTab? get currentTab =>
      tabs.isNotEmpty && currentTabIndex < tabs.length ? tabs[currentTabIndex] : null;

  SessionState copyWith({
    List<EditorTab>? tabs,
    int? currentTabIndex,
  }) {
    return SessionState(
      tabs: tabs ?? List.from(this.tabs),
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
    );
  }

  // --- Serialization ---
  Map<String, dynamic> toJson() => {
        'tabs': tabs.map((t) => t.toJson()).toList(),
        'currentTabIndex': currentTabIndex,
      };

  // Deserialization happens in ProjectManager as it needs access to plugins
}

// --- Editor Tab Models (Mostly Unchanged) ---

abstract class EditorTab {
  final DocumentFile file;
  final EditorPlugin plugin;
  bool isDirty;

  EditorTab({required this.file, required this.plugin, this.isDirty = false});

  String get contentString;
  void dispose();

  EditorTab copyWith({DocumentFile? file, EditorPlugin? plugin, bool? isDirty});

  Map<String, dynamic> toJson();
}

class CodeEditorTab extends EditorTab {
  final CodeLineEditingController controller;
  final CodeCommentFormatter commentFormatter;
  final String? languageKey;

  CodeEditorTab({
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
        'type': 'code', // Add a type for deserialization
        'fileUri': file.uri,
        'pluginType': plugin.runtimeType.toString(),
        'languageKey': languageKey,
        'isDirty': isDirty,
      };
}