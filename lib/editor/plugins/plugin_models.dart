// =========================================
// FILE: lib/editor/plugins/plugin_models.dart
// =========================================

// lib/editor/plugins/plugin_models.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/file_handler/file_handler.dart';
import '../../command/command_models.dart';
import '../editor_tab_models.dart';
import '../../settings/settings_models.dart';

enum PluginDataRequirement { string, bytes }

abstract class EditorPlugin {
  String get name;
  Widget get icon;
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  List<Command> getCommands();
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item);

  bool supportsFile(DocumentFile file);

  // REFACTORED: Add the optional 'id' parameter for rehydration.
  Future<EditorTab> createTab(DocumentFile file, dynamic data, {String? id});
  
  Widget buildEditor(EditorTab tab, WidgetRef ref);

  // --- NEW METHOD FOR CACHING ---
  /// Serializes the "hot" (unsaved) state from a live editor widget.
  ///
  /// This method uses the tab's `editorKey` to access the widget's State
  /// and extract any data that needs to be cached, like unsaved text or
  /// image manipulations.
  ///
  /// Returns a JSON-encodable map of the state, or `null` if the plugin
  /// has no hot state to cache or if the editor is not active.
  Future<Map<String, dynamic>?> serializeHotState(EditorTab tab);
  // --- END OF NEW METHOD ---

  void activateTab(EditorTab tab, Ref ref);
  void deactivateTab(EditorTab tab, Ref ref);

  void disposeTab(EditorTab tab) {}

  PluginSettings? get settings;
  Widget buildSettingsUI(PluginSettings settings);

  Widget buildToolbar(WidgetRef ref) {
    return const SizedBox.shrink();
  }

  Future<EditorTab> createTabFromSerialization(
    Map<String, dynamic> tabJson,
    FileHandler fileHandler,
  );

  Future<void> dispose() async {}
}

abstract class PluginSettings extends MachineSettings {
  //  Map<String, dynamic> toJson();
  //  void fromJson(Map<String, dynamic> json);
}