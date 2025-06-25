// =========================================
// FILE: lib/editor/editor_tab_models.dart
// =========================================

// lib/editor/editor_tab_models.dart
import 'package:flutter/material.dart';
import 'plugins/plugin_models.dart';
import 'package:uuid/uuid.dart';
import 'tab_state_manager.dart'; // ADDED

@immutable
class TabSessionState {
  final List<EditorTab> tabs;
  final int currentTabIndex;
  // ADDED: The metadata map for persistence.
  final Map<String, TabMetadata> tabMetadata;

  const TabSessionState({
    this.tabs = const [],
    this.currentTabIndex = 0,
    this.tabMetadata = const {}, // ADDED
  });

  EditorTab? get currentTab =>
      tabs.isNotEmpty && currentTabIndex < tabs.length
          ? tabs[currentTabIndex]
          : null;

  TabSessionState copyWith({
    List<EditorTab>? tabs,
    int? currentTabIndex,
    Map<String, TabMetadata>? tabMetadata, // ADDED
  }) {
    return TabSessionState(
      tabs: tabs ?? List.from(this.tabs),
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      tabMetadata: tabMetadata ?? this.tabMetadata, // ADDED
    );
  }

  // REFACTORED: toJson now serializes the metadata map.
  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'currentTabIndex': currentTabIndex,
    'tabMetadata': tabMetadata.map((key, value) => MapEntry(key, value.toJson())),
  };

  // REFACTORED: fromJson now deserializes the metadata.
  factory TabSessionState.fromJson(Map<String, dynamic> json) {
    final metadataJson = json['tabMetadata'] as Map<String, dynamic>? ?? {};
    final tabMetadata = metadataJson.map(
      (key, value) => MapEntry(key, TabMetadata.fromJson(value)),
    );

    return TabSessionState(
      tabs: const [], // Tabs are rehydrated by EditorService.
      currentTabIndex: json['currentTabIndex'] ?? 0,
      tabMetadata: tabMetadata,
    );
  }
}

// ... (WorkspaceTab and EditorTab are unchanged) ...
@immutable
abstract class WorkspaceTab {
  final String id;
  final EditorPlugin plugin;

  WorkspaceTab({required this.plugin}) : id = const Uuid().v4();

  void dispose();
}

@immutable
abstract class EditorTab extends WorkspaceTab {
  final GlobalKey<State<StatefulWidget>> editorKey;

  EditorTab({required super.plugin})
      : editorKey = GlobalKey<State<StatefulWidget>>();

  EditorTab copyWith({EditorPlugin? plugin});

  @override
  void dispose();

  Map<String, dynamic> toJson();
}