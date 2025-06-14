// lib/plugins/recipe_tex/recipe_tex_models.dart

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/file_handler/file_handler.dart';
import '../../session/session_models.dart';
import '../plugin_models.dart';

// MODIFIED: This is now a pure "cold" state data class.
// It has no data, only its identity and a reference to its plugin.
@immutable
class RecipeTexTab extends EditorTab {
  const RecipeTexTab({
    required super.file,
    required super.plugin,
  });

  @override
  void dispose() {}

  RecipeTexTab copyWith({
    DocumentFile? file,
    EditorPlugin? plugin,
  }) {
    return RecipeTexTab(
      file: file ?? this.file,
      plugin: plugin ?? this.plugin,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'recipe',
        'fileUri': file.uri,
        'pluginType': plugin.runtimeType.toString(),
      };
}

class InstructionStep {
  String title;
  String content;

  InstructionStep(this.title, this.content);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstructionStep &&
          title == other.title &&
          content == other.content;

  @override
  int get hashCode => Object.hash(title, content);

  InstructionStep copyWith({
    String? title,
    String? content,
  }) {
    return InstructionStep(
      title ?? this.title,
      content ?? this.content,
    );
  }
}

class Ingredient {
  String quantity;
  String unit;
  String name;

  Ingredient(this.quantity, this.unit, this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ingredient &&
          quantity == other.quantity &&
          unit == other.unit &&
          name == other.name;

  @override
  int get hashCode => Object.hash(quantity, unit, name);

  Ingredient copyWith({
    String? quantity,
    String? unit,
    String? name,
  }) {
    return Ingredient(
      quantity ?? this.quantity,
      unit ?? this.unit,
      name ?? this.name,
    );
  }
}

class RecipeData {
  String title = '';
  int acidRefluxScore = 1;
  String acidRefluxReason = '';
  String prepTime = '';
  String cookTime = '';
  String portions = '';
  String image = '';
  List<Ingredient> ingredients = [];
  List<InstructionStep> instructions = [];
  String notes = '';
  String rawImagesSection = '';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipeData &&
          title == other.title &&
          acidRefluxScore == other.acidRefluxScore &&
          acidRefluxReason == other.acidRefluxReason &&
          prepTime == other.prepTime &&
          cookTime == other.cookTime &&
          portions == other.portions &&
          image == other.image &&
          listEquals(ingredients, other.ingredients) &&
          listEquals(instructions, other.instructions) &&
          notes == other.notes &&
          rawImagesSection == other.rawImagesSection;

  @override
  int get hashCode => Object.hash(
        title,
        acidRefluxScore,
        acidRefluxReason,
        prepTime,
        cookTime,
        portions,
        image,
        Object.hashAll(ingredients),
        Object.hashAll(instructions),
        notes,
        rawImagesSection,
      );

  RecipeData copyWith({
    String? title,
    int? acidRefluxScore,
    String? acidRefluxReason,
    String? prepTime,
    String? cookTime,
    String? portions,
    String? image,
    List<Ingredient>? ingredients,
    List<InstructionStep>? instructions,
    String? notes,
    String? rawImagesSection,
  }) {
    return RecipeData()
      ..title = title ?? this.title
      ..acidRefluxScore = acidRefluxScore ?? this.acidRefluxScore
      ..acidRefluxReason = acidRefluxReason ?? this.acidRefluxReason
      ..prepTime = prepTime ?? this.prepTime
      ..cookTime = cookTime ?? this.cookTime
      ..portions = portions ?? this.portions
      ..image = image ?? this.image
      ..ingredients = ingredients != null
          ? ingredients.map((i) => i.copyWith()).toList()
          : this.ingredients.map((i) => i.copyWith()).toList()
      ..instructions = instructions != null
          ? instructions.map((i) => i.copyWith()).toList()
          : this.instructions.map((i) => i.copyWith()).toList()
      ..notes = notes ?? this.notes
      ..rawImagesSection = rawImagesSection ?? this.rawImagesSection;
  }
}