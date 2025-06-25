// =========================================
// FILE: lib/editor/editor_tab_models.dart
// =========================================

import 'package:flutter/material.dart';
import 'plugins/plugin_models.dart';
import 'package:uuid/uuid.dart';
import 'tab_state_manager.dart';

@immutable
class TabSessionState {
  final List<EditorTab> tabs;
  final int currentTabIndex;
  final Map<String, TabMetadata> tabMetadata;

  const TabSessionState({
    this.tabs = const [],
    this.currentTabIndex = 0,
    this.tabMetadata = const {},
  });

  EditorTab? get currentTab =>
      tabs.isNotEmpty && currentTabIndex < tabs.length
          ? tabs[currentTabIndex]
          : null;

  TabSessionState copyWith({
    List<EditorTab>? tabs,
    int? currentTabIndex,
    Map<String, TabMetadata>? tabMetadata,
  }) {
    return TabSessionState(
      tabs: tabs ?? List.from(this.tabs),
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      tabMetadata: tabMetadata ?? Map.from(this.tabMetadata),
    );
  }

  // toJson is correct. It prepares the data for persistence.
  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'currentTabIndex': currentTabIndex,
    'tabMetadata': tabMetadata.map((key, value) => MapEntry(key, value.toJson())),
  };

  // REMOVED: The flawed fromJson factory is gone.
  // factory TabSessionState.fromJson(Map<String, dynamic> json) { ... }
}

// ... (WorkspaceTab and EditorTab are unchanged) ...
@immutable
abstract class WorkspaceTab {
  final String id;
  final EditorPlugin plugin;

  WorkspaceTab({required this.plugin, String? id}) : id = id ?? const Uuid().v4();

  void dispose();
}

@immutable
abstract class EditorTab extends WorkspaceTab {
  final GlobalKey<State<StatefulWidget>> editorKey;

  EditorTab({required super.plugin, super.id})
      : editorKey = GlobalKey<State<StatefulWidget>>();

  @override
  void dispose();

  Map<String, dynamic> toJson();
}