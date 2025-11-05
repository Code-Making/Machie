// =========================================
// FINAL CORRECTED FILE: lib/editor/plugins/recipe_tex/recipe_tex_models.dart
// =========================================

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import '../../models/editor_tab_models.dart';
import 'recipe_editor_widget.dart';

// RecipeTexTab is unchanged and correct.
@immutable
class RecipeTexTab extends EditorTab {
  @override
  final GlobalKey<RecipeEditorWidgetState> editorKey;
  final String initialContent;
  final String? initialBaseContentHash;
  final RecipeData? hotStateData;

  RecipeTexTab({
    required super.plugin,
    required this.initialContent,
    this.initialBaseContentHash,
    this.hotStateData,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<RecipeEditorWidgetState>();

  @override
  void dispose() {}
}

@immutable
class InstructionStep {
  final String title;
  final String content;

  const InstructionStep(this.title, this.content);

  factory InstructionStep.fromJson(Map<String, dynamic> json) =>
      InstructionStep(json['title'] as String, json['content'] as String);

  Map<String, dynamic> toJson() => {'title': title, 'content': content};

  InstructionStep copyWith({String? title, String? content}) {
    return InstructionStep(title ?? this.title, content ?? this.content);
  }

  // ===================================
  //           THE FIX IS HERE
  // ===================================
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstructionStep &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          content == other.content;

  @override
  int get hashCode => title.hashCode ^ content.hashCode;
}

@immutable
class Ingredient {
  final String quantity;
  final String unit;
  final String name;

  const Ingredient(this.quantity, this.unit, this.name);

  factory Ingredient.fromJson(Map<String, dynamic> json) => Ingredient(
    json['quantity'] as String,
    json['unit'] as String,
    json['name'] as String,
  );

  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'unit': unit,
    'name': name,
  };

  Ingredient copyWith({String? quantity, String? unit, String? name}) {
    return Ingredient(
      quantity ?? this.quantity,
      unit ?? this.unit,
      name ?? this.name,
    );
  }

  // ===================================
  //           THE FIX IS HERE
  // ===================================
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ingredient &&
          runtimeType == other.runtimeType &&
          quantity == other.quantity &&
          unit == other.unit &&
          name == other.name;

  @override
  int get hashCode => quantity.hashCode ^ unit.hashCode ^ name.hashCode;
}

// RecipeData is now also fully value-equatable because its children are.
@immutable
class RecipeData {
  final String title;
  final int acidRefluxScore;
  final String acidRefluxReason;
  final String prepTime;
  final String cookTime;
  final String portions;
  final String image;
  final List<Ingredient> ingredients;
  final List<InstructionStep> instructions;
  final String notes;
  final String rawImagesSection;

  const RecipeData({
    this.title = '',
    this.acidRefluxScore = 1,
    this.acidRefluxReason = '',
    this.prepTime = '',
    this.cookTime = '',
    this.portions = '',
    this.image = '',
    this.ingredients = const [],
    this.instructions = const [],
    this.notes = '',
    this.rawImagesSection = '',
  });

  factory RecipeData.fromJson(Map<String, dynamic> json) {
    final ingredientsList =
        (json['ingredients'] as List<dynamic>? ?? [])
            .map((item) => Ingredient.fromJson(Map<String, dynamic>.from(item)))
            .toList();
    final instructionsList =
        (json['instructions'] as List<dynamic>? ?? [])
            .map(
              (item) =>
                  InstructionStep.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
    return RecipeData(
      title: json['title'] as String? ?? '',
      acidRefluxScore: json['acidRefluxScore'] as int? ?? 1,
      acidRefluxReason: json['acidRefluxReason'] as String? ?? '',
      prepTime: json['prepTime'] as String? ?? '',
      cookTime: json['cookTime'] as String? ?? '',
      portions: json['portions'] as String? ?? '',
      image: json['image'] as String? ?? '',
      ingredients: ingredientsList,
      instructions: instructionsList,
      notes: json['notes'] as String? ?? '',
      rawImagesSection: json['rawImagesSection'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'acidRefluxScore': acidRefluxScore,
    'acidRefluxReason': acidRefluxReason,
    'prepTime': prepTime,
    'cookTime': cookTime,
    'portions': portions,
    'image': image,
    'ingredients': ingredients.map((i) => i.toJson()).toList(),
    'instructions': instructions.map((i) => i.toJson()).toList(),
    'notes': notes,
    'rawImagesSection': rawImagesSection,
  };

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
    return RecipeData(
      title: title ?? this.title,
      acidRefluxScore: acidRefluxScore ?? this.acidRefluxScore,
      acidRefluxReason: acidRefluxReason ?? this.acidRefluxReason,
      prepTime: prepTime ?? this.prepTime,
      cookTime: cookTime ?? this.cookTime,
      portions: portions ?? this.portions,
      image: image ?? this.image,
      ingredients: ingredients ?? this.ingredients,
      instructions: instructions ?? this.instructions,
      notes: notes ?? this.notes,
      rawImagesSection: rawImagesSection ?? this.rawImagesSection,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    // Use a specific ListEquality checker for the lists.
    const listEquals = ListEquality();

    return other is RecipeData &&
        other.runtimeType == runtimeType &&
        other.title == title &&
        other.acidRefluxScore == acidRefluxScore &&
        other.acidRefluxReason == acidRefluxReason &&
        other.prepTime == prepTime &&
        other.cookTime == cookTime &&
        other.portions == portions &&
        other.image == image &&
        // Use the list equality checker here.
        listEquals.equals(other.ingredients, ingredients) &&
        listEquals.equals(other.instructions, instructions) &&
        other.notes == notes &&
        other.rawImagesSection == rawImagesSection;
  }

  @override
  int get hashCode {
    // Use a specific ListEquality checker for hashing the lists' contents.
    const listEquals = ListEquality();

    return Object.hash(
      runtimeType,
      title,
      acidRefluxScore,
      acidRefluxReason,
      prepTime,
      cookTime,
      portions,
      image,
      // Use the list equality checker for consistent hashing.
      listEquals.hash(ingredients),
      listEquals.hash(instructions),
      notes,
      rawImagesSection,
    );
  }
}
