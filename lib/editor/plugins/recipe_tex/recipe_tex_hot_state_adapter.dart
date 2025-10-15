// =========================================
// UPDATED: lib/editor/plugins/recipe_tex/recipe_tex_hot_state_adapter.dart
// =========================================
import '../../../data/cache/type_adapters.dart';
import 'recipe_tex_hot_state.dart';
import 'recipe_tex_models.dart';

/// A type adapter for serializing and deserializing [RecipeTexHotStateDto].
class RecipeTexHotStateAdapter implements TypeAdapter<RecipeTexHotStateDto> {
  static const String _dataKey = 'data';
  static const String _hashKey = 'baseContentHash';

  @override
  RecipeTexHotStateDto fromJson(Map<String, dynamic> json) {
    // THE FIX:
    // The value of json[_dataKey] is a Map<dynamic, dynamic> from Hive.
    // We must explicitly create a new Map<String, dynamic> from it before
    // passing it to RecipeData.fromJson.
    final dataMap = Map<String, dynamic>.from(json[_dataKey]);

    return RecipeTexHotStateDto(
      data: RecipeData.fromJson(dataMap),
      baseContentHash: json[_hashKey] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson(RecipeTexHotStateDto object) {
    return {
      _dataKey: object.data.toJson(),
      _hashKey: object.baseContentHash,
    };
  }
}