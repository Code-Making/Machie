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

abstract class PluginSettings extends MachineSettings {
  //  Map<String, dynamic> toJson();
  //  void fromJson(Map<String, dynamic> json);
}
