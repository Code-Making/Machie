// =========================================
// FILE: lib/editor/editor_tab_models.dart
// =========================================

// lib/editor/editor_tab_models.dart
import 'package:flutter/material.dart';
import 'plugins/plugin_models.dart';
// import '../data/file_handler/file_handler.dart'; // REMOVED
import 'package:uuid/uuid.dart';

@immutable
class TabSessionState {
  final List<EditorTab> tabs;
  final int currentTabIndex;

  const TabSessionState({this.tabs = const [], this.currentTabIndex = 0});

  EditorTab? get currentTab =>
      tabs.isNotEmpty && currentTabIndex < tabs.length
          ? tabs[currentTabIndex]
          : null;

  TabSessionState copyWith({List<EditorTab>? tabs, int? currentTabIndex}) {
    return TabSessionState(
      tabs: tabs ?? List.from(this.tabs),
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
    );
  }

  Map<String, dynamic> toJson() => {
    // We only need to serialize the tab IDs, as metadata is now separate.
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'currentTabIndex': currentTabIndex,
  };

  factory TabSessionState.fromJson(Map<String, dynamic> json) {
    return TabSessionState(
      tabs: const [], // Tabs are rehydrated by EditorService.
      currentTabIndex: json['currentTabIndex'] ?? 0,
    );
  }
}

@immutable
abstract class WorkspaceTab {
  // REFACTORED: The stable ID is now on the base class.
  final String id;
  final EditorPlugin plugin;

  WorkspaceTab({required this.plugin}) : id = const Uuid().v4();

  void dispose();
}

@immutable
abstract class EditorTab extends WorkspaceTab {
  // REFACTORED: file and title are removed. They now live in TabMetadata.
  // final DocumentFile file;
  final GlobalKey<State<StatefulWidget>> editorKey;

  EditorTab({required super.plugin})
      : editorKey = GlobalKey<State<StatefulWidget>>();

  // REFACTORED: The copyWith method is now much simpler.
  // In practice, this abstract class will likely never be copied directly.
  EditorTab copyWith({EditorPlugin? plugin});

  @override
  void dispose();

  // The JSON representation of a tab is now its identity and type,
  // which is used to find its metadata during rehydration.
  Map<String, dynamic> toJson();
}