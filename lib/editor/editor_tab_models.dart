// lib/editor/editor_tab_models.dart
import 'package:flutter/material.dart';
import 'plugins/plugin_models.dart';
import '../data/file_handler/file_handler.dart';

// ... TabSessionState is unchanged ...
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

// ... WorkspaceTab is unchanged ...
@immutable
abstract class WorkspaceTab {
  String get title;
  final EditorPlugin plugin;

  const WorkspaceTab({required this.plugin});

  void dispose();
}

@immutable
abstract class EditorTab extends WorkspaceTab {
  final DocumentFile file;

  // NEW: A generalized GlobalKey. It's generic to hold the state of any editor widget.
  final GlobalKey<State<StatefulWidget>> editorKey;

  EditorTab({required this.file, required super.plugin})
    // The key is created with each new tab instance.
    : editorKey = GlobalKey<State<StatefulWidget>>();

  @override
  String get title => file.name;

  EditorTab copyWith({DocumentFile? file, EditorPlugin? plugin});

  @override
  void dispose();

  Map<String, dynamic> toJson();
}
