// lib/editor/plugins/plugin_models.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/file_handler/file_handler.dart';
import '../../command/command_models.dart';
import '../editor_tab_models.dart';
import '../tab_state_manager.dart'; // REFACTOR: Import TabState

enum PluginDataRequirement { string, bytes }

abstract class EditorPlugin {
  String get name;
  Widget get icon;
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  List<Command> getCommands();
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item);

  bool supportsFile(DocumentFile file);
  
  Future<EditorTab> createTab(DocumentFile file, dynamic data);
  Widget buildEditor(EditorTab tab, WidgetRef ref);

  void activateTab(EditorTab tab, Ref ref);
  void deactivateTab(EditorTab tab, Ref ref);
  
  // REFACTOR: Add createTabState method
  /// Creates a transient state object for a tab.
  /// This state (e.g., controllers, undo history) lives as long as the tab is open.
  /// Return null if the plugin's tabs are stateless.
  Future<TabState?> createTabState(EditorTab tab);

  // REFACTOR: Add disposeTabState method
  /// Called when a tab is closed, allowing the plugin to dispose of resources
  /// held by the TabState object (e.g., controllers).
  void disposeTabState(TabState state);

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

abstract class PluginSettings {
  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);
}