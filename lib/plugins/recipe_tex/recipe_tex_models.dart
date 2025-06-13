// lib/plugins/recipe_tex/recipe_tex_models.dart
import 'package:flutter/foundation.dart';
import 'package:machine/plugins/recipe_tex/recipe_tex_plugin.dart';

import '../../../data/file_handler/file_handler.dart';
import '../../../session/session_models.dart';
import '../../plugin_models.dart';

class RecipeTexTab extends EditorTab {
  final RecipeData data;
  final RecipeData originalData;

  final List<RecipeData> undoStack;
  final List<RecipeData> redoStack;

  const RecipeTexTab({
    required super.file,
    required super.plugin,
    required this.data,
    required this.originalData,
    super.isDirty = false,
    this.undoStack = const [],
    this.redoStack = const [],
  });

  @override
  String get contentString =>
      (plugin as RecipeTexPlugin).generateTexContent(data);

  @override
  void dispose() {}

  @override
  RecipeTexTab copyWith({
    DocumentFile? file,
    EditorPlugin? plugin,
    RecipeData? data,
    RecipeData? originalData,
    bool? isDirty,
    List<RecipeData>? undoStack,
    List<RecipeData>? redoStack,
  }) {
    return RecipeTexTab(
      file: file ?? this.file,
      plugin: plugin ?? this.plugin,
      data: data ?? this.data.copyWith(),
      originalData: originalData ?? this.originalData.copyWith(),
      isDirty: isDirty ?? this.isDirty,
      undoStack: undoStack ?? List.from(this.undoStack),
      redoStack: redoStack ?? List.from(this.redoStack),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'recipe',
        'fileUri': file.uri,
        'pluginType': plugin.runtimeType.toString(),
        'isDirty': isDirty,
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
      ..ingredients = ingredients ?? List.from(this.ingredients)
      ..instructions = instructions ?? List.from(this.instructions)
      ..notes = notes ?? this.notes
      ..rawImagesSection = rawImagesSection ?? this.rawImagesSection;
  }
}

