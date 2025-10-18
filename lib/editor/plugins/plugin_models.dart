// =========================================
// UPDATED: lib/editor/plugins/plugin_models.dart
// =========================================

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/type_adapters.dart';
import '../../data/dto/tab_hot_state_dto.dart';
import '../../data/file_handler/file_handler.dart';
import '../../command/command_models.dart';
import '../editor_tab_models.dart';
import '../../settings/settings_models.dart';

enum PluginDataRequirement { string, bytes }

class EditorInitData {
  final String? stringData;
  final Uint8List? byteData;
  final TabHotStateDto? hotState;
  final String? baseContentHash; // <-- ADDED

  const EditorInitData({
    this.stringData,
    this.byteData,
    this.hotState,
    this.baseContentHash, // <-- ADDED
  });
}

abstract class EditorPlugin {
  String get id;
  String get name;
  Widget get icon;
  int get priority;

  // --- Default Implementations for Optional Methods ---

  /// The data requirement for the plugin. Defaults to string-based.
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  /// A quick, metadata-based check. Defaults to false.
  bool supportsFile(DocumentFile file) => false;

  /// A content-based check. Defaults to `false` for binary plugins,
  /// otherwise `true`. Plugins should override for specific content sniffing.
  bool canOpenFileContent(String content, DocumentFile file) {
    return dataRequirement == PluginDataRequirement.string;
  }

  /// Optional command "slots" for the UI. Defaults to an empty list.
  List<CommandPosition> getCommandPositions() => [];

  /// Plugin-specific commands. Defaults to an empty list.
  List<Command> getCommands() => [];

  /// App-wide commands provided by the plugin. Defaults to an empty list.
  List<Command> getAppCommands() => [];

  /// Context menu commands for files. Defaults to an empty list.
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];

  /// Optional plugin-specific settings. Defaults to null.
  PluginSettings? get settings => null;

  /// UI for editing plugin-specific settings. Defaults to an empty widget.
  Widget buildSettingsUI(PluginSettings settings) => const SizedBox.shrink();
  
  /// A way for plugins to wrap toolbars (e.g., to handle focus).
  /// Defaults to returning the toolbar unmodified.
  Widget wrapCommandToolbar(Widget toolbar) => toolbar;
  
  /// A way for plugins to provide their own bottom toolbar.
  /// Defaults to an empty widget.
  Widget buildToolbar(WidgetRef ref) => const SizedBox.shrink();

  /// Lifecycle hook for when a tab becomes active. Defaults to no-op.
  void activateTab(EditorTab tab, Ref ref) {}
  
  /// Lifecycle hook for when a tab becomes inactive. Defaults to no-op.
  void deactivateTab(EditorTab tab, Ref ref) {}
  
  /// Lifecycle hook for when a tab is permanently closed. Defaults to no-op.
  void disposeTab(EditorTab tab) {}
  
  /// Lifecycle hook for when the plugin is unloaded. Defaults to no-op.
  Future<void> dispose() async {}

  // --- Explicit Serialization Contract ---
  
  /// A unique string identifying the type of the hot state DTO for this plugin.
  /// Must be implemented if the plugin supports caching.
  String? get hotStateDtoType;
  
  /// The runtime `Type` of the hot state DTO.
  /// Must be implemented if the plugin supports caching.
  Type? get hotStateDtoRuntimeType;
  
  /// The adapter for serializing/deserializing the DTO.
  /// Must be implemented if the plugin supports caching.
  TypeAdapter<TabHotStateDto>? get hotStateAdapter;

  // --- Abstract Methods (Must be Implemented) ---
  
  /// Creates a new tab instance. The implementation of this method is
  /// responsible for passing the necessary parts of `initData` (like
  /// initial content, cached content, and hash) to its concrete Tab
  /// class constructor. The `EditorTab` itself will not store `initData`.
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  });

  /// Creates the main editor UI widget for a given tab.
  /// The returned widget MUST extend `EditorWidget`.
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref);
    
}

abstract class PluginSettings extends MachineSettings {}
