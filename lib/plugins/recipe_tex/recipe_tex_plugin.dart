// lib/plugins/recipe_tex/recipe_tex_plugin.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../command/command_models.dart';
import '../../command/command_notifier.dart';
import '../../command/command_widgets.dart';
import '../../data/file_handler/file_handler.dart';
import '../../session/session_models.dart';
import '../../utils/logs.dart';
import '../plugin_models.dart';
import 'recipe_tex_editor_ui.dart';
import 'recipe_tex_models.dart';

/// Custom exception for when a .tex file is not a valid recipe.
class InvalidRecipeFormatException extends Error {}

class RecipeTexPlugin implements EditorPlugin {
  @override
  String get name => 'Recipe Editor';

  @override
  Widget get icon => const Icon(Icons.restaurant);

  @override
  PluginSettings? get settings => null;

  @override
  Widget buildSettingsUI(PluginSettings settings) => const SizedBox.shrink();

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.endsWith('.tex');
  }

  @override
  Future<EditorTab> createTab(DocumentFile file, String content) async {
    final recipeData = _parseRecipeContent(content);
    return RecipeTexTab(
      file: file,
      plugin: this,
      data: recipeData,
      originalData: recipeData.copyWith(), // Important for isDirty tracking
      isDirty: false,
    );
  }

  @override
  Future<EditorTab> createTabFromSerialization(
    Map<String, dynamic> tabJson,
    FileHandler fileHandler,
  ) async {
    final fileUri = tabJson['fileUri'] as String;
    final file = await fileHandler.getFileMetadata(fileUri);
    if (file == null) {
      throw Exception('File not found for tab URI: $fileUri');
    }
    final content = await fileHandler.readFile(fileUri);
    return createTab(file, content);
  }

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];

  RecipeData _parseRecipeContent(String content) {
    final recipeData = RecipeData();
    
    final recipeMatch = RegExp(
      r'\\recipe\[(.*?)\]{(.*?)}{(.*?)}{(.*?)}{(.*?)}{(.*?)}\n\n',
      dotAll: true
    ).firstMatch(content);
    
    if (recipeMatch == null) {
      throw InvalidRecipeFormatException();
    }

    if (recipeMatch != null) {
      // Parse basic info
      recipeData.image = recipeMatch.group(1) ?? '';
      recipeData.portions = _extractCommandContent(recipeMatch.group(3)!, r'portion') ?? '';

      // Parse header
      final headerContent = recipeMatch.group(2)!;
      recipeData.title = _extractCommandContent(headerContent, r'recipetitle') ?? '';
      final acidRefluxContent =_extractReflux(headerContent);
      recipeData.acidRefluxScore = int.tryParse(acidRefluxContent[0]) ?? 0;
      recipeData.acidRefluxReason = acidRefluxContent[1]?? '';
      recipeData.prepTime = _extractCommandContent(headerContent, r'preptime') ?? '';
      recipeData.cookTime = _extractCommandContent(headerContent, r'cooktime') ?? '';

      // Parse ingredients
      recipeData.ingredients = _extractListItems(recipeMatch.group(4)!);

      // Parse instructions with titles
      recipeData.instructions = _extractInstructionItems(recipeMatch.group(5)!);

      // Parse notes
      print(recipeMatch.group(6));
      recipeData.notes = _extractCommandContent(recipeMatch.group(6)!, r'info') ?? '';
    }

    // Parse images
      final imagesMatch = RegExp(r'(% Images[\s\S]*)').firstMatch(content);
      if (imagesMatch != null) {
        recipeData.rawImagesSection = imagesMatch.group(1) ?? '';
      }

    return recipeData;
  }
  
List<String> _extractReflux(String latexContent) {
  final regex = RegExp(
    r'\\acidreflux{([^}]+)}\%\n{([^}]*)}',
    caseSensitive: false,
    multiLine: true,
  );

  final match = regex.firstMatch(latexContent);
  if (match == null || match.groupCount < 2) {
    return ['0', '']; // Default values if not found
  }

  final score = match.group(1)?.trim() ?? '0';
  final reason = match.group(2)?.trim() ?? '';

  return [score, reason];
}

  String? _extractCommandContent(String content, String command) {
    final match = RegExp('\\\\$command{(.*?)}', dotAll: true).firstMatch(content);
    return match?.group(1);
  }

  // Update parsing logic
List<Ingredient> _extractListItems(String content) {
  return RegExp(r'\\item\s+(.*?)\s*$', multiLine:true)
      .allMatches(content)
      .map((m) => _parseIngredient(m.group(1)!))
      .toList();
}

Ingredient _parseIngredient(String line) {
  final match = RegExp(r'\\unit(?:\[(.*?)\])?\{(.*?)\}\s*(.*)').firstMatch(line);
  return match != null
      ? Ingredient(
          match.group(1) ?? '', // Quantity
          match.group(2) ?? '', // Unit
          match.group(3) ?? '', // Name
        )
      : Ingredient('', '', line); // Fallback for invalid format
}
  
  List<InstructionStep> _extractInstructionItems(String content) {
    return RegExp(r'\\instruction\{(.*)\}$', multiLine:true)
        .allMatches(content)
        .map((m) => _parseInstruction(m.group(1)!))
        .toList();
  }

  InstructionStep _parseInstruction(String instruction) {
    final titleMatch = RegExp(r'\\textbf\{\\large\s*(.*?)\}\s*(.*)').firstMatch(instruction);
    return titleMatch != null 
        ? InstructionStep(titleMatch.group(1)!, titleMatch.group(2)!.trim())
        : InstructionStep('', instruction);
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final recipeTab = tab as RecipeTexTab;
    return RecipeEditorForm(data: recipeTab.data);
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    return const BottomToolbar();
  }

  @override
  Future<void> dispose() async {}

  @override
  void activateTab(EditorTab tab, Ref ref) {}

  @override
  void deactivateTab(EditorTab tab, Ref ref) {}



  @override
  List<Command> getCommands() => [
        BaseCommand(
          id: 'copy_recipe',
          label: 'Copy LaTeX',
          icon: const Icon(Icons.copy),
          defaultPosition: CommandPosition.pluginToolbar,
          sourcePlugin: runtimeType.toString(),
          execute: (ref) async {
            final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
            if (tab is RecipeTexTab) {
              await Clipboard.setData(ClipboardData(text: tab.contentString));
              ref.read(logProvider.notifier).add('Copied recipe to clipboard');
            }
          },
          canExecute: (ref) => ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab is RecipeTexTab)),
        ),
        BaseCommand(
          id: 'save_recipe',
          label: 'Save Recipe',
          icon: const Icon(Icons.save),
          defaultPosition: CommandPosition.pluginToolbar,
          sourcePlugin: runtimeType.toString(),
          execute: (ref) async {
            final appNotifier = ref.read(appNotifierProvider.notifier);
            final oldTab = ref.read(appNotifierProvider).value!.currentProject!.session.currentTab as RecipeTexTab;
            
            await appNotifier.saveCurrentTab();

            // After saving, update the originalData to reset the dirty state.
            final savedTab = oldTab.copyWith(
              originalData: oldTab.data.copyWith(),
              isDirty: false,
            );
            appNotifier.updateCurrentTab(savedTab);
            
            ref.read(logProvider.notifier).add('Recipe saved successfully');
          },
          canExecute: (ref) => ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.isDirty ?? false)),
        ),
        BaseCommand(
          id: 'undo_recipe',
          label: 'Undo',
          icon: const Icon(Icons.undo),
          defaultPosition: CommandPosition.pluginToolbar,
          sourcePlugin: runtimeType.toString(),
          execute: (ref) async {
            final appNotifier = ref.read(appNotifierProvider.notifier);
            final currentTab = ref.read(appNotifierProvider).value!.currentProject!.session.currentTab;
            if (currentTab is! RecipeTexTab || currentTab.undoStack.isEmpty) return;

            final previousData = currentTab.undoStack.last;
            final newTab = currentTab.copyWith(
              data: previousData,
              undoStack: currentTab.undoStack.sublist(0, currentTab.undoStack.length - 1),
              redoStack: [currentTab.data, ...currentTab.redoStack],
              isDirty: previousData != currentTab.originalData,
            );
            appNotifier.updateCurrentTab(newTab);
          },
          canExecute: (ref) {
            final tab = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab));
            return tab is RecipeTexTab && tab.undoStack.isNotEmpty;
          },
        ),
        BaseCommand(
          id: 'redo_recipe',
          label: 'Redo',
          icon: const Icon(Icons.redo),
          defaultPosition: CommandPosition.pluginToolbar,
          sourcePlugin: runtimeType.toString(),
          execute: (ref) async {
            final appNotifier = ref.read(appNotifierProvider.notifier);
            final currentTab = ref.read(appNotifierProvider).value!.currentProject!.session.currentTab;
            if (currentTab is! RecipeTexTab || currentTab.redoStack.isEmpty) return;
            
            final nextData = currentTab.redoStack.first;
            final newTab = currentTab.copyWith(
              data: nextData,
              undoStack: [...currentTab.undoStack, currentTab.data],
              redoStack: currentTab.redoStack.sublist(1),
              isDirty: nextData != currentTab.originalData,
            );
            appNotifier.updateCurrentTab(newTab);
          },
          canExecute: (ref) {
            final tab = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab));
            return tab is RecipeTexTab && tab.redoStack.isNotEmpty;
          },
        ),
      ];
      

  // Update the Tex generation
String generateTexContent(RecipeData data) {
  final buffer = StringBuffer();
  
  buffer.writeln('\\recipe[${data.image}]{');
  buffer.writeln('\\recipetitle{${data.title}}');
  buffer.writeln('\\acidreflux{${data.acidRefluxScore}}%\n{${data.acidRefluxReason}}');
  buffer.writeln('\\preptime{${data.prepTime}} \\cooktime{${data.cookTime}}');
  buffer.writeln('}{\\portion{${data.portions}}}{');
  
  // Ingredients
  for (final ingredient in data.ingredients) {
    final quantityPart = ingredient.quantity.isNotEmpty 
        ? '[${ingredient.quantity}]'
        : '';
    buffer.writeln(
      '  \\item \\unit$quantityPart{${ingredient.unit}} ${ingredient.name}'
    );
  }
  buffer.writeln('}{');
  
  // Instructions
  for (final instruction in data.instructions) {
    if (instruction.title.isNotEmpty) {
      buffer.writeln('  \\instruction{\\textbf{\\large ${instruction.title}} ${instruction.content}}');
    } else {
      buffer.writeln('  \\instruction{${instruction.content}}');
    }
  }
  buffer.writeln('}{');
  
  // Notes
  buffer.writeln(' \\info{${data.notes}}');
  buffer.writeln('}');
  
  if (data.rawImagesSection.isNotEmpty) {
    buffer.writeln('\n${data.rawImagesSection}');
  }
  
  return buffer.toString();
  }
}

