// lib/plugins/plugin_architecture.dart

import 'dart:async';
// NEW IMPORT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/file_handler/file_handler.dart';
import '../../command/command_models.dart';
import '../editor_tab_models.dart';

// NEW: Enum to declare what kind of data the plugin expects.
enum PluginDataRequirement { string, bytes }

// --------------------
//   Editor Plugin
// --------------------

abstract class EditorPlugin {
  String get name;
  Widget get icon;

  // NEW: Property to declare data needs. Defaults to string for backward compatibility.
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  List<Command> getCommands();
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item);

  bool supportsFile(DocumentFile file);

  // MODIFIED: `data` is now `dynamic` to accept String or Uint8List.
  Future<EditorTab> createTab(DocumentFile file, dynamic data);
  Widget buildEditor(EditorTab tab, WidgetRef ref);

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

abstract class PluginSettings {
  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);
}
