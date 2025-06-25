// =========================================
// FILE: lib/editor/editor_tab_models.dart
// =========================================

import 'package:flutter/material.dart';
import 'plugins/plugin_models.dart';
import 'package:uuid/uuid.dart';
import 'tab_state_manager.dart';
import 'package:machine/data/dto/project_dto.dart'; // ADDED

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
  
  TabSessionStateDto toDto(Map<String, TabMetadata> liveMetadata) {
    return TabSessionStateDto(
      tabs: tabs.map((t) => t.toDto()).toList(),
      currentTabIndex: currentTabIndex,
      tabMetadata: liveMetadata.map((key, value) => MapEntry(key, TabMetadataDto(
        fileUri: value.file.uri,
        isDirty: value.isDirty,
      ))),
    );
  }

  EditorTab? get currentTab =>
      tabs.isNotEmpty && currentTabIndex < tabs.length
          ? tabs[currentTabIndex]
          : null;

  TabSessionState copyWith({
    List<EditorTab>? tabs,
    int? currentTabIndex,
  }) {
    return TabSessionState(
      tabs: tabs ?? List.from(this.tabs),
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
    );
  }
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

  EditorTabDto toDto() {
    return EditorTabDto(
      id: id,
      pluginType: plugin.runtimeType.toString(),
    );
  }
}