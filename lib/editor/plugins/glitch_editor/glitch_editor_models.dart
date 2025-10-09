// =========================================
// FILE: lib/editor/plugins/glitch_editor/glitch_editor_models.dart
// =========================================

// lib/plugins/glitch_editor/glitch_editor_models.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
// import '../../../data/file_handler/file_handler.dart'; // REMOVED
import '../../editor_tab_models.dart';
import '../../editor_tab_models.dart';
import 'glitch_editor_widget.dart';
@immutable
class GlitchEditorTab extends EditorTab {
  // ADDED: The key is now created and stored here with the correct concrete state type.
  @override
  final GlobalKey<GlitchEditorWidgetState> editorKey;

  final Uint8List initialImageData;
  final Uint8List? cachedImageData;
  final String? initialBaseContentHash;

  GlitchEditorTab({
    required super.plugin,
    required this.initialImageData,
    this.cachedImageData,
    this.initialBaseContentHash,
    super.id,
  // ADDED: Initialize the key in the constructor.
  }) : editorKey = GlobalKey<GlitchEditorWidgetState>();

  @override
  void dispose() {}

  Map<String, dynamic> toJson() => {
    'type': 'glitch',
    'id': id,
    'pluginType': plugin.runtimeType.toString(),
    'fileUri': '',
  };
}

// ... GlitchBrush models are unchanged ...
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
