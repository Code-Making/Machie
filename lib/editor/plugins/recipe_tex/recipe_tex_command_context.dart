// =========================================
// NEW FILE: lib/editor/plugins/recipe_tex/recipe_tex_command_context.dart
// =========================================
import 'package:flutter/foundation.dart';
import 'package:machine/editor/plugins/editor_command_context.dart';

@immutable
class RecipeTexCommandContext extends CommandContext {
  final bool canUndo;
  final bool canRedo;

  const RecipeTexCommandContext({
    this.canUndo = false,
    this.canRedo = false,
  }) : super(appBarOverride: null);
}