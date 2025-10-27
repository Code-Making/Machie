// =========================================
// UPDATED: lib/editor/plugins/glitch_editor/glitch_editor_hot_state_adapter.dart
// =========================================

import 'dart:convert';
// ADDED
import '../../../data/cache/type_adapters.dart';
import 'glitch_editor_hot_state_dto.dart';

/// A type adapter for serializing and deserializing [GlitchEditorHotStateDto].
class GlitchEditorHotStateAdapter
    implements TypeAdapter<GlitchEditorHotStateDto> {
  static const String _imageDataKey = 'imageData';
  static const String _hashKey = 'baseContentHash'; // <-- ADDED

  @override
  GlitchEditorHotStateDto fromJson(Map<String, dynamic> json) {
    final base64String = json[_imageDataKey] as String? ?? '';
    final imageData = base64Decode(base64String);

    return GlitchEditorHotStateDto(
      imageData: imageData,
      baseContentHash: json[_hashKey] as String?, // <-- ADDED
    );
  }

  @override
  Map<String, dynamic> toJson(GlitchEditorHotStateDto object) {
    final base64String = base64Encode(object.imageData);
    return {
      _imageDataKey: base64String,
      _hashKey: object.baseContentHash, // <-- ADDED
    };
  }
}
