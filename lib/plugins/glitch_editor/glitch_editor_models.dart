// lib/plugins/glitch_editor/glitch_editor_models.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../data/file_handler/file_handler.dart';
import '../../session/session_models.dart';
import '../plugin_models.dart';

// The "cold" data handle for a tab. Contains no mutable state.
@immutable
class GlitchEditorTab extends EditorTab {
  const GlitchEditorTab({
    required super.file,
    required super.plugin,
  });

  @override
  void dispose() {}

  @override
  Map<String, dynamic> toJson() => {
        'type': 'glitch',
        'fileUri': file.uri,
        'pluginType': plugin.runtimeType.toString(),
      };
}

// The settings for the currently selected brush.
enum GlitchBrushType { scatter, repeater }

class GlitchBrushSettings {
  GlitchBrushType type;
  double radius;
  double density; // For scatter brush
  int repeatSpacing; // For repeater brush

  GlitchBrushSettings({
    this.type = GlitchBrushType.scatter,
    this.radius = 20.0,
    this.density = 0.5,
    this.repeatSpacing = 20,
  });

  GlitchBrushSettings copyWith({
    GlitchBrushType? type,
    double? radius,
    double? density,
    int? repeatSpacing,
  }) {
    return GlitchBrushSettings(
      type: type ?? this.type,
      radius: radius ?? this.radius,
      density: density ?? this.density,
      repeatSpacing: repeatSpacing ?? this.repeatSpacing,
    );
  }
}