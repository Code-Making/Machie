// =========================================
// NEW FILE: lib/editor/plugins/glitch_editor/glitch_editor_hot_state_dto.dart
// =========================================

import 'package:flutter/foundation.dart';
import '../../../data/dto/tab_hot_state_dto.dart';

/// A DTO representing the unsaved state of the [GlitchEditorPlugin].
@immutable
class GlitchEditorHotStateDto implements TabHotStateDto {
  /// The raw, manipulated image data as a list of bytes (e.g., a PNG).
  final Uint8List imageData;

  const GlitchEditorHotStateDto({required this.imageData});
}
