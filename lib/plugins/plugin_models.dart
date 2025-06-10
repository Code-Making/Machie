// lib/plugins/plugin_architecture.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/file_handler/file_handler.dart';
import '../command/command_models.dart';
import '../session/session_models.dart';

// --------------------
//   Editor Plugin
// --------------------

abstract class EditorPlugin {
  String get name;
  Widget get icon;
  List<Command> getCommands();
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item);

  bool supportsFile(DocumentFile file);

  Future<EditorTab> createTab(DocumentFile file, String content);
  Widget buildEditor(EditorTab tab, WidgetRef ref);

  // CORRECTED: Signature now uses the more generic `Ref`
  void activateTab(EditorTab tab, Ref ref);
  void deactivateTab(EditorTab tab, Ref ref);

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
