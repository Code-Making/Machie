// lib/session/session_models.dart
import 'package:collection/collection.dart';
import 'package:re_editor/re_editor.dart';
import 'package:flutter/material.dart';

import '../plugins/plugin_models.dart';
import '../data/file_handler/file_handler.dart';

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

  Map<String, dynamic> toJson() => {
        'tabs': tabs.map((t) => t.toJson()).toList(),
        'currentTabIndex': currentTabIndex,
      };
}

@immutable
abstract class EditorTab {
  final DocumentFile file;
  final EditorPlugin plugin;
  final bool isDirty; // CORRECTED: Made final for immutability

  const EditorTab({required this.file, required this.plugin, this.isDirty = false});

  String get contentString;
  void dispose();

  EditorTab copyWith({DocumentFile? file, EditorPlugin? plugin, bool? isDirty});

  Map<String, dynamic> toJson();
}