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
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  // ADDED: Allows plugins to declare their own command "slots".
  List<CommandPosition> getCommandPositions() => [];

  List<Command> getCommands();
  List<Command> getAppCommands() => [];
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item);

  bool supportsFile(DocumentFile file);

  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
  });
  Widget buildEditor(EditorTab tab, WidgetRef ref);

  String? get hotStateDtoType;
  Type? get hotStateDtoRuntimeType;
  TypeAdapter<TabHotStateDto>? get hotStateAdapter;
  Future<TabHotStateDto?> serializeHotState(EditorTab tab);

  void activateTab(EditorTab tab, Ref ref);
  void deactivateTab(EditorTab tab, Ref ref);
  void disposeTab(EditorTab tab) {}
  PluginSettings? get settings;
  Widget buildSettingsUI(PluginSettings settings);

  Widget wrapCommandToolbar(Widget toolbar) => toolbar;

  Widget buildToolbar(WidgetRef ref) => const SizedBox.shrink();

  Future<EditorTab> createTabFromSerialization(
    Map<String, dynamic> tabJson,
    FileHandler fileHandler,
  );
  Future<void> dispose() async {}
}

abstract class PluginSettings extends MachineSettings {}
