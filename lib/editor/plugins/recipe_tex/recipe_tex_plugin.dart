// =========================================
// UPDATED: lib/editor/plugins/recipe_tex/recipe_tex_plugin.dart
// =========================================
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
  }) async {
    RecipeData? hotStateData;
    if (initData.hotState is RecipeTexHotStateDto) {
      hotStateData = (initData.hotState as RecipeTexHotStateDto).data;
    }

    return RecipeTexTab(
      plugin: this,
      id: id,
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

  static String generateTexContent(RecipeData data) {
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
    final recipeData = RecipeData();
    final recipeMatch = RegExp(r'\\recipe\[(.*?)\]{(.*?)}{(.*?)}{(.*?)}{(.*?)}{(.*?)}\n\n', dotAll: true).firstMatch(content);
    if (recipeMatch != null) {
      recipeData.image = recipeMatch.group(1) ?? '';
      recipeData.portions = _extractCommandContent(recipeMatch.group(3)!, r'portion') ?? '';
      final headerContent = recipeMatch.group(2)!;
      recipeData.title = _extractCommandContent(headerContent, r'recipetitle') ?? '';
      final acidRefluxContent = _extractReflux(headerContent);
      recipeData.acidRefluxScore = int.tryParse(acidRefluxContent[0]) ?? 0;
      recipeData.acidRefluxReason = acidRefluxContent[1] ?? '';
      recipeData.prepTime = _extractCommandContent(headerContent, r'preptime') ?? '';
      recipeData.cookTime = _extractCommandContent(headerContent, r'cooktime') ?? '';
      recipeData.ingredients = _extractListItems(recipeMatch.group(4)!);
      recipeData.instructions = _extractInstructionItems(recipeMatch.group(5)!);
      recipeData.notes = _extractCommandContent(recipeMatch.group(6)!, r'info') ?? '';
    }
    final imagesMatch = RegExp(r'(% Images[\s\S]*)').firstMatch(content);
    if (imagesMatch != null) recipeData.rawImagesSection = imagesMatch.group(1) ?? '';
    return recipeData;
  }
  List<String> _extractReflux(String latexContent) {
    final regex = RegExp(r'\\acidreflux{([^}]+)}\s*%\s*\n\s*{([^}]*)}', multiLine: true);
    final match = regex.firstMatch(latexContent);
    if (match == null || match.groupCount < 2) return ['0', ''];
    return [match.group(1)?.trim() ?? '0', match.group(2)?.trim() ?? ''];
  }
  String? _extractCommandContent(String content, String command) => RegExp('\\\\$command{(.*?)}', dotAll: true).firstMatch(content)?.group(1);
  List<Ingredient> _extractListItems(String content) => RegExp(r'\\item\s+(.*?)\s*$', multiLine: true).allMatches(content).map((m) => _parseIngredient(m.group(1)!)).toList();
  Ingredient _parseIngredient(String line) {
    final match = RegExp(r'\\unit(?:\[(.*?)\])?\{(.*?)\}\s*(.*)').firstMatch(line);
    return match != null ? Ingredient(match.group(1) ?? '', match.group(2) ?? '', match.group(3) ?? '') : Ingredient('', '', line);
  }
  List<InstructionStep> _extractInstructionItems(String content) => RegExp(r'\\instruction\{(.*)\}\s*$', multiLine: true).allMatches(content).map((m) => _parseInstruction(m.group(1)!)).toList();
  InstructionStep _parseInstruction(String instruction) {
    final titleMatch = RegExp(r'\\textbf\{\\large\s*(.*?)\}\s*(.*)').firstMatch(instruction);
    return titleMatch != null ? InstructionStep(titleMatch.group(1)!, titleMatch.group(2)!.trim()) : InstructionStep('', instruction);
  }
}
