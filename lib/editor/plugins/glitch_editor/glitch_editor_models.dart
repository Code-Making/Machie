// =========================================
// FILE: lib/editor/plugins/glitch_editor/glitch_editor_models.dart
// =========================================

// lib/plugins/glitch_editor/glitch_editor_models.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
// import '../../../data/file_handler/file_handler.dart'; // REMOVED
import '../../editor_tab_models.dart';
import '../plugin_models.dart';

@immutable
class GlitchEditorTab extends EditorTab {
  final Uint8List initialImageData;

  GlitchEditorTab({
    required super.plugin,
    required this.initialImageData,
    super.id, // ADDED
  });

  @override
  void dispose() {}

  @override
  Map<String, dynamic> toJson() => {
    'type': 'glitch',
    'id': id, // Serialize the stable ID
    'pluginType': plugin.runtimeType.toString(),
    // We need to persist the file URI to reopen the tab.
    // This will be read by the EditorService during rehydration.
    // It's a bit of a workaround since the file is in metadata,
    // but essential for persistence. A better way might be to persist
    // the entire metadata map.
    'fileUri': '', // This would be populated from metadata on save.
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