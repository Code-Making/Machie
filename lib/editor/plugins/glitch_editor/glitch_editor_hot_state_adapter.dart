// =========================================
// UPDATED: lib/editor/plugins/glitch_editor/glitch_editor_hot_state_adapter.dart
// =========================================

import 'dart:convert'; // ADDED: Required for base64Encode and base64Decode.
import 'dart:typed_data';
import '../../../data/cache/type_adapters.dart';
import 'glitch_editor_hot_state_dto.dart';

/// A type adapter for serializing and deserializing [GlitchEditorHotStateDto].
class GlitchEditorHotStateAdapter implements TypeAdapter<GlitchEditorHotStateDto> {
  static const String _imageDataKey = 'imageData';

  // REFACTORED: This method now correctly handles binary-to-text conversion.
  @override
  GlitchEditorHotStateDto fromJson(Map<String, dynamic> json) {
    // 1. Get the Base64 string from the JSON map.
    final base64String = json[_imageDataKey] as String? ?? '';
    
    // 2. Decode the Base64 string back into its original binary (Uint8List) form.
    final imageData = base64Decode(base64String);
    
    return GlitchEditorHotStateDto(
      imageData: imageData,
    );
  }

  // REFACTORED: This method now correctly handles text-to-binary conversion.
  @override
  Map<String, dynamic> toJson(GlitchEditorHotStateDto object) {
    // 1. Convert the binary imageData (Uint8List) into a text-safe Base64 string.
    final base64String = base64Encode(object.imageData);
    
    // 2. Store the Base64 string in the JSON map.
    return {
      _imageDataKey: base64String,
    };
  }
}