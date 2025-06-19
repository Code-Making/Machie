import 'package:flutter/material.dart';

import 'plugins/plugin_models.dart';
import '../data/file_handler/file_handler.dart';

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
}

@immutable
abstract class WorkspaceTab {
  String get title; // MODIFIED
  final EditorPlugin plugin;

  const WorkspaceTab({required this.plugin});

  void dispose();
}

@immutable
abstract class EditorTab extends WorkspaceTab {
  final DocumentFile file;

  // MODIFIED: Constructor is 'const' again and no longer calls super with a title.
  const EditorTab({required this.file, required super.plugin});

  // MODIFIED: Implement the 'title' getter here.
  @override
  String get title => file.name;

  @override
  void dispose();

  Map<String, dynamic> toJson();
}
