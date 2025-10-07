// =========================================
// UPDATED: lib/editor/plugins/glitch_editor/glitch_editor_hot_state_dto.dart
// =========================================

import 'dart:typed_data'; // ADDED
import 'package:flutter/foundation.dart';
import '../../../data/dto/tab_hot_state_dto.dart';

/// A DTO representing the unsaved state of the [GlitchEditorPlugin].
@immutable
class GlitchEditorHotStateDto extends TabHotStateDto {
  /// The raw, manipulated image data as a list of bytes (e.g., a PNG).
  final Uint8List imageData;

  const GlitchEditorHotStateDto({
    required this.imageData,
    super.baseContentHash, // <-- ADDED
  });
}