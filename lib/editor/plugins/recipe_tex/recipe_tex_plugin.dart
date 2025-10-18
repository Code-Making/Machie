// =========================================
// UPDATED: lib/editor/plugins/recipe_tex/recipe_tex_plugin.dart
// =========================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../command/command_widgets.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../editor_tab_models.dart';
import '../../tab_state_manager.dart';
import '../../plugins/editor_command_context.dart';
import '../../services/editor_service.dart';
import '../plugin_models.dart';
import 'recipe_editor_widget.dart';
import 'recipe_tex_command_context.dart';
import 'recipe_tex_hot_state.dart';
import 'recipe_tex_hot_state_adapter.dart';
import 'recipe_tex_models.dart';
import '../../../utils/toast.dart';

class RecipeTexPlugin extends EditorPlugin {
  static const String pluginId = 'com.machine.recipe_tex';
  static const String hotStateId = 'com.machine.recipe_tex_state';

  @override
  String get id => pluginId;
  @override
  String get name => 'Recipe Editor';
  @override
  Widget get icon => const Icon(Icons.restaurant_menu);
  @override
  int get priority => 10; // High priority to claim .tex files over code editor

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;
  @override
  final PluginSettings? settings = null;
  @override
  Widget buildSettingsUI(PluginSettings settings) => const SizedBox.shrink();

  @override
  bool supportsFile(DocumentFile file) => file.name.endsWith('.tex');

  @override
  bool canOpenFileContent(String content, DocumentFile file) {
    // Content validation using the provided regex.
    return RegExp(r'\\recipe\[.*?\]{', dotAll: true).hasMatch(content);
  }

  @override
  String get hotStateDtoType => hotStateId;
  @override
  Type? get hotStateDtoRuntimeType => RecipeTexHotStateDto;
  @override
  TypeAdapter<TabHotStateDto> get hotStateAdapter => RecipeTexHotStateAdapter();

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    RecipeData? hotStateData;
    if (initData.hotState is RecipeTexHotStateDto) {
      hotStateData = (initData.hotState as RecipeTexHotStateDto).data;
    }

    return RecipeTexTab(
      plugin: this,
      id: id,
      onReadyCompleter: onReadyCompleter,
      initialContent: initData.stringData ?? '',
      initialBaseContentHash: initData.baseContentHash,
      hotStateData: hotStateData,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    final recipeTab = tab as RecipeTexTab;
    return RecipeEditorWidget(key: recipeTab.editorKey, tab: recipeTab);
  }

  @override
  Widget buildToolbar(WidgetRef ref) => const BottomToolbar();

  @override
  Future<void> dispose() async {}
  @override
  void disposeTab(EditorTab tab) {}
  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];
  @override
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}
  @override
  List<CommandPosition> getCommandPositions() => [];

  /// Helper to get the active editor's state object.
  RecipeEditorWidgetState? _getActiveEditorState(WidgetRef ref) {
    final tab = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab));
    if (tab is! RecipeTexTab) return null;
    return tab.editorKey.currentState as RecipeEditorWidgetState?;
  }

  @override
  List<Command> getAppCommands() => [];
  
  @override
  List<Command> getCommands() => [
    BaseCommand(
      id: 'save',
      label: 'Save Recipe',
      icon: const Icon(Icons.save),
      defaultPositions: [AppCommandPositions.appBar],
      sourcePlugin: id,
      execute: (ref) async => ref.read(editorServiceProvider).saveCurrentTab(),
      canExecute: (ref) {
        final tabId = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.id));
        if (tabId == null) return false;
        final isDirty = ref.watch(tabMetadataProvider.select((m) => m[tabId]?.isDirty ?? false));
        return isDirty;
      },
    ),
    BaseCommand(
      id: 'copy_latex',
      label: 'Copy LaTeX',
      icon: const Icon(Icons.copy),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async {
        final content = await _getActiveEditorState(ref)?.getTexContent();
        if (content != null) {
          await Clipboard.setData(ClipboardData(text: content));
          MachineToast.info('Copied LaTeX to clipboard');
        }
      },
      canExecute: (ref) => _getActiveEditorState(ref) != null,
    ),
    BaseCommand(
      id: 'undo',
      label: 'Undo',
      icon: const Icon(Icons.undo),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.undo(),
      canExecute: (ref) {
        final context = ref.watch(activeCommandContextProvider);
        return (context is RecipeTexCommandContext) && context.canUndo;
      },
    ),
    BaseCommand(
      id: 'redo',
      label: 'Redo',
      icon: const Icon(Icons.redo),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.redo(),
      canExecute: (ref) {
        final context = ref.watch(activeCommandContextProvider);
        return (context is RecipeTexCommandContext) && context.canRedo;
      },
    ),
  ];

  // These parsing/generation functions are now static as they don't depend on instance state.
  static String generateTexContent(RecipeData data) {
     // ... (generation logic is unchanged, just moved)
    final buffer = StringBuffer();
    buffer.writeln('\\recipe[${data.image}]{');
    buffer.writeln('\\recipetitle{${data.title}}');
    buffer.writeln('\\acidreflux{${data.acidRefluxScore}}%\\n{${data.acidRefluxReason}}');
    buffer.writeln('\\preptime{${data.prepTime}} \\cooktime{${data.cookTime}}');
    buffer.writeln('}{\\portion{${data.portions}}}{');
    for (final ingredient in data.ingredients) {
      final quantityPart = ingredient.quantity.isNotEmpty ? '[${ingredient.quantity}]' : '';
      buffer.writeln('  \\item \\unit$quantityPart{${ingredient.unit}} ${ingredient.name}');
    }
    buffer.writeln('}{');
    for (final instruction in data.instructions) {
      if (instruction.title.isNotEmpty) {
        buffer.writeln('  \\instruction{\\textbf{\\large ${instruction.title}} ${instruction.content}}');
      } else {
        buffer.writeln('  \\instruction{${instruction.content}}');
      }
    }
    buffer.writeln('}{');
    buffer.writeln(' \\info{${data.notes}}');
    buffer.writeln('}');
    if (data.rawImagesSection.isNotEmpty) buffer.writeln('\n${data.rawImagesSection}');
    return buffer.toString();
  }
  
  static RecipeData parseRecipeContent(String content) {
    // 1. Initialize local variables with default values.
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

    final recipeMatch = RegExp(
      r'\\recipe\[(.*?)\]{(.*?)}{(.*?)}{(.*?)}{(.*?)}{(.*?)}',
      dotAll: true,
    ).firstMatch(content);

    if (recipeMatch != null) {
      // 2. Assign parsed values to the local variables, not the object.
      image = recipeMatch.group(1) ?? '';
      
      final headerContent = recipeMatch.group(2) ?? '';
      final portionsContent = recipeMatch.group(3) ?? '';
      final ingredientsContent = recipeMatch.group(4) ?? '';
      final instructionsContent = recipeMatch.group(5) ?? '';
      final notesContent = recipeMatch.group(6) ?? '';
      
      title = _extractCommandContent(headerContent, r'recipetitle') ?? '';
      final acidRefluxParts = _extractReflux(headerContent);
      acidRefluxScore = int.tryParse(acidRefluxParts[0]) ?? 1;
      acidRefluxReason = acidRefluxParts[1];
      prepTime = _extractCommandContent(headerContent, r'preptime') ?? '';
      cookTime = _extractCommandContent(headerContent, r'cooktime') ?? '';
      
      portions = _extractCommandContent(portionsContent, r'portion') ?? '';
      
      ingredients = _extractListItems(ingredientsContent);
      instructions = _extractInstructionItems(instructionsContent);
      
      notes = _extractCommandContent(notesContent, r'info') ?? '';
    }

    final imagesMatch = RegExp(r'(% Images[\s\S]*)').firstMatch(content);
    if (imagesMatch != null) {
      rawImagesSection = imagesMatch.group(1) ?? '';
    }

    // 3. Construct the immutable RecipeData object at the end.
    return RecipeData(
      title: title,
      acidRefluxScore: acidRefluxScore,
      acidRefluxReason: acidRefluxReason,
      prepTime: prepTime,
      cookTime: cookTime,
      portions: portions,
      image: image,
      ingredients: ingredients,
      instructions: instructions,
      notes: notes,
      rawImagesSection: rawImagesSection,
    );
  }

  // --- Helper Parsing Functions ---

  /// Extracts the score and reason from the special `\acidreflux{score}%\n{reason}` format.
  static List<String> _extractReflux(String latexContent) {
    final regex = RegExp(r'\\acidreflux{([^}]+)}\s*%\s*\\n\s*{([^}]*)}', multiLine: true);
    final match = regex.firstMatch(latexContent);
    if (match == null || match.groupCount < 2) return ['1', ''];
    return [match.group(1)?.trim() ?? '1', match.group(2)?.trim() ?? ''];
  }

  /// A generic helper to extract content from a simple `\command{content}` format.
  static String? _extractCommandContent(String content, String command) {
    return RegExp('\\\\$command{(.*?)}', dotAll: true).firstMatch(content)?.group(1);
  }

  /// Finds all `\item ...` lines in the ingredients block and parses them individually.
  static List<Ingredient> _extractListItems(String content) {
    return RegExp(r'\\item\s+(.*?)\s*$', multiLine: true)
        .allMatches(content)
        .map((m) => _parseIngredient(m.group(1)!))
        .toList();
  }

  /// Parses a single ingredient line, e.g., `\unit[1]{cup} Flour`.
  static Ingredient _parseIngredient(String line) {
    // This regex handles an optional quantity in square brackets.
    final match = RegExp(r'\\unit(?:\[(.*?)\])?\{(.*?)\}\s*(.*)').firstMatch(line);
    if (match != null) {
      // Group 1: Optional quantity
      // Group 2: Unit
      // Group 3: Name
      return Ingredient(match.group(1) ?? '', match.group(2) ?? '', match.group(3)?.trim() ?? '');
    }
    // Fallback if the format is unexpected
    return Ingredient('', '', line.trim());
  }

  /// Finds all `\instruction{...}` lines and parses them individually.
  static List<InstructionStep> _extractInstructionItems(String content) {
    return RegExp(r'\\instruction\{(.*)\}\s*$', multiLine: true)
        .allMatches(content)
        .map((m) => _parseInstruction(m.group(1)!))
        .toList();
  }

  /// Parses a single instruction, checking for an optional bolded title.
  static InstructionStep _parseInstruction(String instruction) {
    // This regex looks for `\textbf{\large TITLE} DETAILS`
    final titleMatch = RegExp(r'\\textbf\{\\large\s*(.*?)\}\s*(.*)', dotAll: true).firstMatch(instruction);
    if (titleMatch != null) {
      // Group 1: Title
      // Group 2: Details
      return InstructionStep(titleMatch.group(1)!, titleMatch.group(2)!.trim());
    }
    // If no title, the whole string is the content.
    return InstructionStep('', instruction.trim());
  }
}
