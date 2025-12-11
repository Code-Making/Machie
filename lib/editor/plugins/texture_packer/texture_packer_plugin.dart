import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/editor/models/editor_plugin_models.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'texture_packer_asset.dart';
import 'texture_packer_editor_models.dart';
import 'texture_packer_editor_widget.dart';
import 'texture_packer_models.dart';

class TexturePackerPlugin extends EditorPlugin {
  @override
  String get id => 'com.machine.texture_packer';

  @override
  String get name => 'Texture Packer';

  @override
  Widget get icon => const Icon(Icons.grid_view);

  @override
  int get priority => 5; // Same as Tiled Editor

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.toLowerCase().endsWith('.tpacker');
  }

  /// Register the custom asset loader for .tpacker files.
  @override
  List<AssetLoader> get assetLoaders => [TexturePackerAssetLoader()];

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    final content = (initData.initialContent as EditorContentString).content;
    
    // Parse the .tpacker file content into our project data model.
    final TexturePackerProject projectState;
    if (content.trim().isEmpty) {
      projectState = TexturePackerProject.fresh();
    } else {
      projectState = TexturePackerProject.fromJson(jsonDecode(content));
    }

    return TexturePackerTab(
      plugin: this,
      initialProjectState: projectState,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return TexturePackerEditorWidget(
      key: (tab as TexturePackerTab).editorKey,
      tab: tab,
    );
  }
  
  // --- Other optional plugin overrides can go here ---

  @override
  String? get hotStateDtoType => null; // Not implemented yet

  @override
  Type? get hotStateDtoRuntimeType => null; // Not implemented yet

  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => null; // Not implemented yet
}