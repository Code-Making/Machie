// =========================================
// UPDATED: lib/editor/plugins/glitch_editor/glitch_editor_hot_state_adapter.dart
// =========================================

import 'package:machine/data/dto/tab_hot_state_dto.dart';
import 'package:machine/data/cache/type_adapters.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'glitch_editor_hot_state_dto.dart';

class GlitchEditorHotStateAdapter
    implements TypeAdapter<GlitchEditorHotStateDto> {
  final _talker = Talker();

  @override
  GlitchEditorHotStateDto fromJson(Map<String, dynamic> json) {
    _talker.info('--> GlitchEditorHotStateAdapter: Deserializing from JSON: $json');
    final dto = GlitchEditorHotStateDto(
      seed: json['seed'],
      resolution: json['resolution'],
      volume: json['volume'],
      speed: json['speed'],
      blendMode: json['blendMode'],
      colorMode: json['colorMode'],
      isGlitching: json['isGlitching'],
      isStatic: json['isStatic'],
      isFreezed: json['isFreezed'],
    );
    _talker.info('--> GlitchEditorHotStateAdapter: Deserialized DTO: $dto');
    return dto;
  }

  @override
  Map<String, dynamic> toJson(GlitchEditorHotStateDto object) {
    _talker.info('--> GlitchEditorHotStateAdapter: Serializing DTO: $object');
    final json = {
      'seed': object.seed,
      'resolution': object.resolution,
      'volume': object.volume,
      'speed': object.speed,
      'blendMode': object.blendMode,
      'colorMode': object.colorMode,
      'isGlitching': object.isGlitching,
      'isStatic': object.isStatic,
      'isFreezed': object.isFreezed,
    };
    _talker.info('--> GlitchEditorHotStateAdapter: Serialized JSON: $json');
    return json;
  }
}