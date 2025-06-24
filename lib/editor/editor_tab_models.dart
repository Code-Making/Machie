// lib/editor/editor_tab_models.dart
import 'package:flutter/material.dart';
import 'plugins/plugin_models.dart';
import '../data/file_handler/file_handler.dart';
import 'package:uuid/uuid.dart'; // NEW IMPORT

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
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'currentTabIndex': currentTabIndex,
  };

  factory TabSessionState.fromJson(Map<String, dynamic> json) {
    return TabSessionState(
      tabs: const [],
      currentTabIndex: json['currentTabIndex'] ?? 0,
    );
  }
}

@immutable
abstract class WorkspaceTab {
  String get title;
  final EditorPlugin plugin;

  const WorkspaceTab({required this.plugin});

  void dispose();
}

@immutable
abstract class EditorTab extends WorkspaceTab {
  // NEW: A stable, unique ID for the lifetime of the tab session.
  final String id;
  final DocumentFile file;
  final GlobalKey<State<StatefulWidget>> editorKey;

  EditorTab({required this.file, required super.plugin})
      : id = const Uuid().v4(), // Generate a unique ID on creation
        editorKey = GlobalKey<State<StatefulWidget>>();

  @override
  String get title => file.name;

  // The copyWith method must now handle the id.
  // When we copy, we are creating a conceptually new tab session,
  // so it's okay for it to get a new key and ID.
  EditorTab copyWith({DocumentFile? file, EditorPlugin? plugin});

  @override
  void dispose();

  Map<String, dynamic> toJson();
}