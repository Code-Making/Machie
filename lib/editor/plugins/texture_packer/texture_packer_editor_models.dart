import 'package:flutter/material.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'texture_packer_editor_widget.dart';
import 'texture_packer_models.dart';

/// Represents an open tab for the Texture Packer editor.
@immutable
class TexturePackerTab extends EditorTab {
  @override
  final GlobalKey<TexturePackerEditorWidgetState> editorKey;
  
  /// The initial state of the texture packer project, parsed from the .tpacker file.
  final TexturePackerProject initialProjectState;

  TexturePackerTab({
    required super.plugin,
    required this.initialProjectState,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<TexturePackerEditorWidgetState>();
  
  @override
  void dispose() {
    // Perform any specific cleanup if needed.
  }
}