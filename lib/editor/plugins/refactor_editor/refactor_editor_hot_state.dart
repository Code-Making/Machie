// =========================================
// NEW FILE: lib/editor/plugins/refactor_editor/refactor_editor_hot_state.dart
// =========================================

import 'package:flutter/foundation.dart';

import '../../../data/cache/type_adapters.dart';
import '../../../data/dto/tab_hot_state_dto.dart';
import 'refactor_editor_models.dart';

/// DTO for serializing the "hot" (unsaved) state of a refactor session.
@immutable
class RefactorEditorHotStateDto extends TabHotStateDto {
  final String searchTerm;
  final String replaceTerm;
  final bool isRegex;
  final bool isCaseSensitive;

  // We only save the core search parameters, not the results,
  // as the results can be regenerated on rehydration.
  const RefactorEditorHotStateDto({
    required this.searchTerm,
    required this.replaceTerm,
    required this.isRegex,
    required this.isCaseSensitive,
    super.baseContentHash,
  });
}

/// Adapter to convert the RefactorEditorHotStateDto to and from JSON.
class RefactorEditorHotStateAdapter implements TypeAdapter<RefactorEditorHotStateDto> {
  @override
  RefactorEditorHotStateDto fromJson(Map<String, dynamic> json) {
    return RefactorEditorHotStateDto(
      searchTerm: json['searchTerm'] as String? ?? '',
      replaceTerm: json['replaceTerm'] as String? ?? '',
      isRegex: json['isRegex'] as bool? ?? false,
      isCaseSensitive: json['isCaseSensitive'] as bool? ?? false,
      baseContentHash: json['baseContentHash'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson(RefactorEditorHotStateDto object) {
    return {
      'searchTerm': object.searchTerm,
      'replaceTerm': object.replaceTerm,
      'isRegex': object.isRegex,
      'isCaseSensitive': object.isCaseSensitive,
      'baseContentHash': object.baseContentHash,
    };
  }
}