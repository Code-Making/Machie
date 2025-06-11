// lib/session/session_models.dart
import 'package:flutter/material.dart';

import '../plugins/plugin_models.dart';
import '../data/file_handler/file_handler.dart';

// NEW: Top-level abstraction for any tab in the workspace.
@immutable
abstract class WorkspaceTab {
  final String title;
  final EditorPlugin plugin;

  const WorkspaceTab({
    required this.title,
    required this.plugin,
  });

  void dispose();
}

@immutable
class SessionState {
  final List<EditorTab> tabs;
  final int currentTabIndex;

  const SessionState({this.tabs = const [], this.currentTabIndex = 0});

  EditorTab? get currentTab =>
      tabs.isNotEmpty && currentTabIndex < tabs.length
          ? tabs[currentTabIndex]
          : null;

  SessionState copyWith({List<EditorTab>? tabs, int? currentTabIndex}) {
    return SessionState(
      tabs: tabs ?? List.from(this.tabs),
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
    );
  }

  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'currentTabIndex': currentTabIndex,
  };
}

@immutable
abstract class EditorTab extends WorkspaceTab { // MODIFIED: extends WorkspaceTab
  final DocumentFile file;
  final bool isDirty;

  // MODIFIED: Removed 'const' because file.name is not a compile-time constant.
  const EditorTab({
    required this.file,
    required super.plugin,
    this.isDirty = false,
  }) : super(title: file.name);

  String get contentString;
  
  // dispose() is already in WorkspaceTab

  EditorTab copyWith({DocumentFile? file, EditorPlugin? plugin, bool? isDirty});

  Map<String, dynamic> toJson();
}