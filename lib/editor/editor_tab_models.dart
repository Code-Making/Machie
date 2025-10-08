// =========================================
// UPDATED: lib/editor/editor_tab_models.dart
// =========================================
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:uuid/uuid.dart';
import '../data/dto/project_dto.dart';
import '../data/dto/tab_hot_state_dto.dart';

import 'plugins/plugin_models.dart';
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

  TabSessionStateDto toDto(Map<String, TabMetadata> liveMetadata) {
    return TabSessionStateDto(
      tabs: tabs.map((t) => t.toDto()).toList(),
      currentTabIndex: currentTabIndex,
      tabMetadata: liveMetadata.map(
        (key, value) => MapEntry(
          key,
          TabMetadataDto(fileUri: value.file.uri, isDirty: value.isDirty),
        ),
      ),
    );
  }

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
}

sealed class EditorContent {}
class EditorContentString extends EditorContent {
  final String content;
  EditorContentString(this.content);
}
class EditorContentBytes extends EditorContent {
  final Uint8List bytes;
  EditorContentBytes(this.bytes);
}


// ### NEW: The contract for any widget that serves as an editor UI.
abstract class EditorWidget extends ConsumerStatefulWidget {
  final EditorTab tab;

  const EditorWidget({required this.tab, required super.key});
}

// ### NEW: The explicit, stateful contract for an EditorWidget.
// This is what plugins MUST implement in their State objects.
abstract class EditorWidgetState<T extends EditorWidget> extends ConsumerState<T> {
  ValueListenable<bool> get dirtyState;
  bool get canUndo;
  bool get canRedo;

  void undo();
  void redo();

  /// Called by the framework when saving. The widget state's only
  /// responsibility is to return its current content in the correct format.
  /// The service will handle the rest (writing, hashing, etc.).
  Future<EditorContent> getContent();

  /// Called by the framework to update the widget's internal baseline hash
  /// after a successful save operation.
  void onSaveSuccess(String newHash);
  
  Future<TabHotStateDto?> serializeHotState();
}

@immutable
abstract class WorkspaceTab {
  final String id;
  final EditorPlugin plugin;

  WorkspaceTab({required this.plugin, String? id})
    : id = id ?? const Uuid().v4();

  void dispose();
}

@immutable
abstract class EditorTab extends WorkspaceTab {
  // MODIFIED: The key is now strongly typed to our new state contract.
  final GlobalKey<EditorWidgetState> editorKey;
  
  EditorTab({
    required super.plugin,
    super.id,
  }) : editorKey = GlobalKey<EditorWidgetState>();

  @override
  void dispose();

  EditorTabDto toDto() {
    return EditorTabDto(id: id, pluginType: plugin.id);
  }
}
