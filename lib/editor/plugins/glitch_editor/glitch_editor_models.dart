// lib/plugins/glitch_editor/glitch_editor_models.dart
import 'dart:typed_data'; // NEW IMPORT for Uint8List
import 'package:flutter/material.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../editor_tab_models.dart';
import '../plugin_models.dart';
import 'glitch_editor_widget.dart'; // NEW IMPORT for the key's State type

@immutable
class GlitchEditorTab extends EditorTab {
  // NEW: The initial raw image data is passed to the widget.
  final Uint8List initialImageData;

  GlitchEditorTab({
    required super.file,
    required super.plugin,
    required this.initialImageData,
  });

  // The key is now inherited from the abstract EditorTab.

  @override
  void dispose() {}

  @override
  GlitchEditorTab copyWith({
    DocumentFile? file,
    EditorPlugin? plugin,
    Uint8List? initialImageData,
  }) {
    // A new key will be created automatically by the EditorTab constructor.
    return GlitchEditorTab(
      file: file ?? this.file,
      plugin: plugin ?? this.plugin,
      initialImageData: initialImageData ?? this.initialImageData,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'glitch',
    'fileUri': file.uri,
    'pluginType': plugin.runtimeType.toString(),
  };
}

enum GlitchBrushType { scatter, repeater, heal }
enum GlitchBrushShape { circle, square }

class GlitchBrushSettings {
  GlitchBrushType type;
  GlitchBrushShape shape;
  double radius;
  double minBlockSize;
  double maxBlockSize;
  double frequency;

  GlitchBrushSettings({
    this.type = GlitchBrushType.scatter,
    this.shape = GlitchBrushShape.circle,
    this.radius = 0.1,
    this.minBlockSize = 2.0,
    this.maxBlockSize = 5.0,
    this.frequency = 0.5,
  });

  GlitchBrushSettings copyWith({
    GlitchBrushType? type,
    GlitchBrushShape? shape,
    double? radius,
    double? minBlockSize,
    double? maxBlockSize,
    double? frequency,
  }) {
    return GlitchBrushSettings(
      type: type ?? this.type,
      shape: shape ?? this.shape,
      radius: radius ?? this.radius,
      minBlockSize: minBlockSize ?? this.minBlockSize,
      maxBlockSize: maxBlockSize ?? this.maxBlockSize,
      frequency: frequency ?? this.frequency,
    );
  }
}