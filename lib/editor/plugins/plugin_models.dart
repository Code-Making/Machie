// =========================================
// UPDATED: lib/editor/plugins/plugin_models.dart
// =========================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/type_adapters.dart'; // ADDED
import '../../data/dto/tab_hot_state_dto.dart'; // ADDED
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
  List<Command> getAppCommands() => []; // Default to an empty list.
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item);

  bool supportsFile(DocumentFile file);

  Future<EditorTab> createTab(DocumentFile file, dynamic data, {String? id});
  Widget buildEditor(EditorTab tab, WidgetRef ref);
  
  // --- UPDATED METHODS & GETTERS FOR CACHING ---
  
  /// A unique string key that identifies this plugin's hot state DTO type.
  /// This is used by the caching system to know which adapter to use for deserialization.
  /// It is recommended to use a reverse domain name convention, e.g., 'com.app.code_editor_state'.
  String? get hotStateDtoType;

  /// The specific [TypeAdapter] for this plugin's [TabHotStateDto].
  /// Returns `null` if the plugin does not support caching its hot state.
  TypeAdapter<TabHotStateDto>? get hotStateAdapter;

  /// Serializes the "hot" (unsaved) state from a live editor widget into a
  /// strongly-typed DTO.
  ///
  /// Returns a [TabHotStateDto] instance, or `null` if there is no state to cache.
  Future<TabHotStateDto?> serializeHotState(EditorTab tab);

  // --- END OF UPDATED SECTION ---

  void activateTab(EditorTab tab, Ref ref);
  void deactivateTab(EditorTab tab, Ref ref);
  void disposeTab(EditorTab tab) {}
  PluginSettings? get settings;
  Widget buildSettingsUI(PluginSettings settings);
  Widget buildToolbar(WidgetRef ref) => const SizedBox.shrink();
  Future<EditorTab> createTabFromSerialization(Map<String, dynamic> tabJson, FileHandler fileHandler);
  Future<void> dispose() async {}
}

abstract class PluginSettings extends MachineSettings { }