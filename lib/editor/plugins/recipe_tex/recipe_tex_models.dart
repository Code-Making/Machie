// =========================================
// UPDATED: lib/editor/plugins/recipe_tex/recipe_tex_models.dart
// =========================================
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../editor_tab_models.dart';
import 'recipe_editor_widget.dart'; // We will create this next

@immutable
class RecipeTexTab extends EditorTab {
  // This tab model now just holds the key to its stateful widget.
  @override
  final GlobalKey<RecipeEditorWidgetState> editorKey;

  final String initialContent;
  final String? initialBaseContentHash;
  // Hot state is now passed directly during creation.
  final RecipeData? hotStateData;

  RecipeTexTab({
    required super.plugin,
    required this.initialContent,
    this.initialBaseContentHash,
    this.hotStateData,
    super.id,
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

  // ADDED: copyWith method for immutable updates.
  InstructionStep copyWith({String? title, String? content}) {
    return InstructionStep(
      title ?? this.title,
      content ?? this.content,
    );
  }
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

  // ADDED: copyWith method for immutable updates.
  Ingredient copyWith({String? quantity, String? unit, String? name}) {
    return Ingredient(
      quantity ?? this.quantity,
      unit ?? this.unit,
      name ?? this.name,
    );
  }
}

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
    return RecipeData(
      title: json['title'] as String? ?? '',
      acidRefluxScore: json['acidRefluxScore'] as int? ?? 1,
      acidRefluxReason: json['acidRefluxReason'] as String? ?? '',
      prepTime: json['prepTime'] as String? ?? '',
      cookTime: json['cookTime'] as String? ?? '',
      portions: json['portions'] as String? ?? '',
      image: json['image'] as String? ?? '',
      ingredients: (json['ingredients'] as List? ?? [])
          .map((i) => Ingredient.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
      instructions: (json['instructions'] as List? ?? [])
          .map((i) => InstructionStep.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
      
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
}