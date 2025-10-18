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

export '../data/dto/tab_hot_state_dto.dart';

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
  @override
  void initState() {
    super.initState();
    // THE FIX: The base class now controls the "ready" signal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // 1. Call the new lifecycle hook for subclasses to perform their setup.
        onFirstFrameReady();
        // 2. ONLY AFTER setup is complete, resolve the completer.
        ref.read(editorServiceProvider).resolveCompleterForTab(widget.tab.id, this);
      }
    });
  }
  
  /// A lifecycle hook called once after the first frame is built.
  /// Subclasses should override this to perform initial setup, like applying
  /// cached content, before the widget is considered fully "ready".
  @protected
  void onFirstFrameReady();

  /// Synchronizes the editor's internal, command-relevant state with the
  /// global `commandContextProvider`. This method is the core of the
  /// reactive command system. It should be called whenever state like
  /// `canUndo`, `canRedo`, or selection changes.
  void syncCommandContext();

  void undo();
  void redo();
  Future<EditorContent> getContent();
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
  // MODIFIED: The key is no longer created here. It's now an abstract getter.
  GlobalKey<EditorWidgetState> get editorKey;
  
  EditorTab({
    required super.plugin,
    super.id,
  });

  @override
  void dispose();

  EditorTabDto toDto() {
    return EditorTabDto(id: id, pluginType: plugin.id);
  }
}
