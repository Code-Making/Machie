// lib/plugins/glitch_editor/glitch_editor_models.dart
import 'package:flutter/material.dart';

import '../../../data/file_handler/file_handler.dart';
import '../../editor_tab_models.dart';
import '../plugin_models.dart';

@immutable
class GlitchEditorTab extends EditorTab {
  const GlitchEditorTab({required super.file, required super.plugin});

  @override
  void dispose() {}

  GlitchEditorTab copyWith({DocumentFile? file, EditorPlugin? plugin}) {
    return GlitchEditorTab(
      file: file ?? this.file,
      plugin: plugin ?? this.plugin,
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
  double radius; // Now a percentage (0.0 to 1.0)
  double minBlockSize;
  double maxBlockSize;
  double frequency; // For both brushes

  GlitchBrushSettings({
    this.type = GlitchBrushType.scatter,
    this.shape = GlitchBrushShape.circle,
    this.radius = 0.1, // Default to 10% of screen width
    this.minBlockSize = 2.0,
    this.maxBlockSize = 5.0,
    this.frequency = 0.5, // 0.0 to 1.0
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
