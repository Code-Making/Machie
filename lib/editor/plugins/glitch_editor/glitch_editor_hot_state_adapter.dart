// =========================================
// NEW FILE: lib/editor/plugins/glitch_editor/glitch_editor_hot_state_adapter.dart
// =========================================

import 'dart:typed_data';
import '../../../data/cache/type_adapters.dart';
import 'glitch_editor_hot_state_dto.dart';

/// A type adapter for serializing and deserializing [GlitchEditorHotStateDto].
class GlitchEditorHotStateAdapter implements TypeAdapter<GlitchEditorHotStateDto> {
  // Define constant keys.
  static const String _imageDataKey = 'imageData';

  @override
  GlitchEditorHotStateDto fromJson(Map<String, dynamic> json) {
    // The image data is stored as a List<int>, which needs to be cast back to Uint8List.
    final imageDataList = json[_imageDataKey] as List<dynamic>? ?? [];
    return GlitchEditorHotStateDto(
      imageData: Uint8List.fromList(imageDataList.cast<int>()),
    );
  }

  @override
  Map<String, dynamic> toJson(GlitchEditorHotStateDto object) {
    return {
      _imageDataKey: object.imageData,
    };
  }
}