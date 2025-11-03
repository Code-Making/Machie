// =========================================
// NEW FILE: lib/editor/plugins/recipe_tex/recipe_tex_hot_state.dart
// =========================================

import 'package:flutter/foundation.dart';

import '../../../data/dto/tab_hot_state_dto.dart';
import 'recipe_tex_models.dart';

/// A DTO representing the unsaved state of the [RecipeTexPlugin].
@immutable
class RecipeTexHotStateDto extends TabHotStateDto {
  /// The full, parsed recipe data that is being edited.
  final RecipeData data;

  const RecipeTexHotStateDto({required this.data, super.baseContentHash});
}
