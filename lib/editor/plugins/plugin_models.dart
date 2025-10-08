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

  /// Defines the order in which plugins are checked. A higher number
  /// indicates a higher priority. This is crucial for specialized editors
  /// (like a Git Diff viewer) to be checked before generic ones.
  int get priority;


  // ADDED: Allows plugins to declare their own command "slots".
  List<CommandPosition> getCommandPositions() => [];

  List<Command> getCommands();
  List<Command> getAppCommands() => [];
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item);

  /// A quick, initial filter based on file metadata (usually the extension).
  /// This is checked before any file content is read.
  bool supportsFile(DocumentFile file);

  /// A more thorough check based on the actual file content. This is only
  /// called for text-based plugins (`PluginDataRequirement.string`) after
  /// the file has been read once.
  ///
  /// The plugin can inspect the content to see if it matches an expected
  /// format (e.g., starts with "diff --git").
  ///
  /// Returns `true` if the plugin can definitively handle this content,
  /// `false` otherwise.
  bool canOpenFileContent(String content, DocumentFile file);


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
