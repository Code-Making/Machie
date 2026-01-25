// FILE: lib/editor/editor_tab_models.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/dto/project_dto.dart';
import '../../data/dto/tab_hot_state_dto.dart';
import '../tab_metadata_notifier.dart';
import 'editor_plugin_models.dart';

import '../../data/content_provider/file_content_provider.dart'; // NEW IMPORT

export '../../data/dto/tab_hot_state_dto.dart';

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

  TabSessionStateDto toDto(
    Map<String, TabMetadata> liveMetadata,
    FileContentProviderRegistry registry, // Pass the registry
  ) {
    return TabSessionStateDto(
      tabs: tabs.map((t) => t.toDto()).toList(),
      currentTabIndex: currentTabIndex,
      tabMetadata: liveMetadata.map(
        (key, value) => MapEntry(
          key,
          TabMetadataDto(
            fileUri: value.file.uri,
            isDirty: value.isDirty,
            fileName: value.file.name,
            // Use the registry to get the type ID
            fileType: registry.getTypeIdForFile(value.file),
          ),
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

abstract class EditorWidget extends ConsumerStatefulWidget {
  final EditorTab tab;

  const EditorWidget({required this.tab, required super.key});
}

abstract class EditorWidgetState<T extends EditorWidget>
    extends ConsumerState<T> {
  @override
  void initState() {
    super.initState();
    init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        onFirstFrameReady();
      }
    });
  }

  // Offers a clean method for state initialization that leaves orchestration to the architecture.
  @protected
  void init();

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

  // REMOVED: canUndo, canRedo are no longer part of the public contract.
  // They will be exposed via the CommandContext.

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
  GlobalKey<EditorWidgetState> get editorKey;

  /// A completer that finishes when the editor widget's state is initialized.
  /// This allows services to await the readiness of an editor before interacting with it.
  final Completer<EditorWidgetState> onReady;

  EditorTab({
    required super.plugin,
    super.id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) : onReady = onReadyCompleter ?? Completer<EditorWidgetState>();

  @override
  void dispose();

  EditorTabDto toDto() {
    return EditorTabDto(id: id, pluginType: plugin.id);
  }
}
