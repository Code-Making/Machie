// lib/plugins/recipe_tex/recipe_tex_plugin.dart

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../command/command_models.dart';
import '../../command/command_widgets.dart';
import '../../data/file_handler/file_handler.dart';
import '../../session/session_models.dart';
import '../../session/tab_state.dart';
import '../plugin_models.dart';
import 'recipe_editor_widget.dart';
import 'recipe_tex_models.dart';

// A private container for a tab's "hot" state.
class _RecipeTabState {
  RecipeData data;
  final RecipeData originalData;
  final List<RecipeData> undoStack;
  final List<RecipeData> redoStack;

  _RecipeTabState({
    required this.data,
    required this.originalData,
    this.undoStack = const [],
    this.redoStack = const [],
  });
}

// --------------------
//  Recipe Tex Plugin
// --------------------
class RecipeTexPlugin implements EditorPlugin {
  // Map to hold the "hot" state for each tab, keyed by file URI.
  final Map<String, _RecipeTabState> _tabStates = {};

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

    // Store the "hot" state internally
    _tabStates[file.uri] = _RecipeTabState(
      data: recipeData,
      originalData: recipeData.copyWith(), // Deep copy for comparison
    );

    // Return the "cold" tab object
    return RecipeTexTab(
      file: file,
      plugin: this,
      data: recipeData,
    );
  }

  @override
  Future<EditorTab> createTabFromSerialization(
      Map<String, dynamic> tabJson, FileHandler fileHandler) async {
    final fileUri = tabJson['fileUri'] as String;
    final file = await fileHandler.getFileMetadata(fileUri);
    if (file == null) {
      throw Exception('File not found for tab URI: $fileUri');
    }
    final content = await fileHandler.readFile(fileUri);
    return createTab(file, content);
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final recipeTab = tab as RecipeTexTab;
    // CORRECTED: Pass the plugin instance to the widget.
    return RecipeEditorForm(tab: recipeTab, plugin: this);
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    return const BottomToolbar();
  }

  @override
  Future<void> dispose() async {
    _tabStates.clear();
  }

  @override
  void disposeTab(EditorTab tab) {
    _tabStates.remove(tab.file.uri);
  }

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];

  @override
  void activateTab(EditorTab tab, Ref ref) {}

  @override
  void deactivateTab(EditorTab tab, Ref ref) {}

  // --- State Management Methods ---

  RecipeData? getDataForTab(RecipeTexTab tab) {
    return _tabStates[tab.file.uri]?.data;
  }

  void updateDataForTab(RecipeTexTab tab,
      RecipeData Function(RecipeData) updater, WidgetRef ref) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;

    final previousData = state.data;
    final newData = updater(previousData.copyWith());

    _tabStates[tab.file.uri] = _RecipeTabState(
      data: newData,
      originalData: state.originalData,
      undoStack: [...state.undoStack, previousData],
      redoStack: [], // Clear redo stack on new action
    );

    // Manually trigger a rebuild of the editor widget by updating the tab object
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final newTab = tab.copyWith(data: newData);
    appNotifier.updateCurrentTab(newTab);

    // Mark tab as dirty
    final isDirty =
        !const DeepCollectionEquality().equals(newData, state.originalData);
    final tabStateNotifier = ref.read(tabStateProvider.notifier);
    if (isDirty) {
      tabStateNotifier.markDirty(tab.file.uri);
    } else {
      tabStateNotifier.markClean(tab.file.uri);
    }
  }

  String _generateTexContent(RecipeData data) {
    final buffer = StringBuffer();

    buffer.writeln('\\recipe[${data.image}]{');
    buffer.writeln('\\recipetitle{${data.title}}');
    buffer.writeln(
        '\\acidreflux{${data.acidRefluxScore}}%\\n{${data.acidRefluxReason}}');
    buffer.writeln('\\preptime{${data.prepTime}} \\cooktime{${data.cookTime}}');
    buffer.writeln('}{\\portion{${data.portions}}}{');

    for (final ingredient in data.ingredients) {
      final quantityPart =
          ingredient.quantity.isNotEmpty ? '[${ingredient.quantity}]' : '';
      buffer.writeln(
          '  \\item \\unit$quantityPart{${ingredient.unit}} ${ingredient.name}');
    }
    buffer.writeln('}{');

    for (final instruction in data.instructions) {
      if (instruction.title.isNotEmpty) {
        buffer.writeln(
            '  \\instruction{\\textbf{\\large ${instruction.title}} ${instruction.content}}');
      } else {
        buffer.writeln('  \\instruction{${instruction.content}}');
      }
    }
    buffer.writeln('}{');

    buffer.writeln(' \\info{${data.notes}}');
    buffer.writeln('}');

    if (data.rawImagesSection.isNotEmpty) {
      buffer.writeln('\n${data.rawImagesSection}');
    }

    return buffer.toString();
  }

  // --- Commands ---
  @override
  List<Command> getCommands() => [
        BaseCommand(
          id: 'recipe_copy_tex',
          label: 'Copy LaTeX',
          icon: const Icon(Icons.copy),
          defaultPosition: CommandPosition.pluginToolbar,
          sourcePlugin: runtimeType.toString(),
          execute: (ref) async {
            final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as RecipeTexTab?;
            if (tab == null) return;
            final state = _tabStates[tab.file.uri];
            if (state == null) return;
            final content = _generateTexContent(state.data);
            await Clipboard.setData(ClipboardData(text: content));
            ref.read(rootScaffoldMessengerKeyProvider).currentState?.showSnackBar(
                  const SnackBar(content: Text('Copied LaTeX to clipboard')));
          },
          canExecute: (ref) =>
              ref.read(appNotifierProvider).value?.currentProject?.session.currentTab
                  is RecipeTexTab,
        ),
        BaseCommand(
            id: 'recipe_save',
            label: 'Save Recipe',
            icon: const Icon(Icons.save),
            defaultPosition: CommandPosition.pluginToolbar,
            sourcePlugin: runtimeType.toString(),
            execute: (ref) async {
              final appNotifier = ref.read(appNotifierProvider.notifier);
              final tab = appNotifier.state.value?.currentProject?.session
                  .currentTab as RecipeTexTab?;
              if (tab == null) return;
              final state = _tabStates[tab.file.uri];
              if (state == null) return;

              final content = _generateTexContent(state.data);
              await appNotifier.saveCurrentTab(content: content);

              _tabStates[tab.file.uri] = _RecipeTabState(
                data: state.data,
                originalData: state.data.copyWith(),
                undoStack: [],
                redoStack: [],
              );
              ref.read(rootScaffoldMessengerKeyProvider).currentState?.showSnackBar(
                  const SnackBar(content: Text('Recipe saved.')));
            },
            canExecute: (ref) {
              final tab = ref
                  .watch(appNotifierProvider)
                  .value
                  ?.currentProject
                  ?.session
                  .currentTab;
              if (tab == null) return false;
              return ref.watch(
                  tabStateProvider.select((s) => s[tab.file.uri] ?? false));
            }),
        BaseCommand(
            id: 'recipe_undo',
            label: 'Undo',
            icon: const Icon(Icons.undo),
            defaultPosition: CommandPosition.pluginToolbar,
            sourcePlugin: runtimeType.toString(),
            execute: (ref) {
              final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as RecipeTexTab?;
              if (tab == null) return false;
              final state = _tabStates[tab.file.uri];
              if (state == null || state.undoStack.isEmpty) return false;

              final lastData = state.undoStack.removeLast();
              _tabStates[tab.file.uri] = _RecipeTabState(
                data: lastData,
                originalData: state.originalData,
                undoStack: state.undoStack,
                redoStack: [state.data, ...state.redoStack],
              );

              ref.read(appNotifierProvider.notifier).updateCurrentTab(
                  tab.copyWith(data: lastData));

              final isDirty = !const DeepCollectionEquality()
                  .equals(lastData, state.originalData);
              ref.read(tabStateProvider.notifier).state = {
                ...ref.read(tabStateProvider),
                tab.file.uri: isDirty
              };
            },
            canExecute: (ref) {
              final tab = ref
                  .watch(appNotifierProvider)
                  .value
                  ?.currentProject
                  ?.session
                  .currentTab;
              return tab is RecipeTexTab &&
                  (_tabStates[tab.file.uri]?.undoStack.isNotEmpty ?? false);
            }),
        BaseCommand(
            id: 'recipe_redo',
            label: 'Redo',
            icon: const Icon(Icons.redo),
            defaultPosition: CommandPosition.pluginToolbar,
            sourcePlugin: runtimeType.toString(),
            execute: (ref) {
              final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as RecipeTexTab?;
              if (tab == null) return false;
              final state = _tabStates[tab.file.uri];
              if (state == null || state.redoStack.isEmpty) return false;

              final nextData = state.redoStack.removeAt(0);
              _tabStates[tab.file.uri] = _RecipeTabState(
                data: nextData,
                originalData: state.originalData,
                undoStack: [...state.undoStack, state.data],
                redoStack: state.redoStack,
              );

              ref.read(appNotifierProvider.notifier).updateCurrentTab(
                  tab.copyWith(data: nextData));

              final isDirty = !const DeepCollectionEquality()
                  .equals(nextData, state.originalData);
              ref.read(tabStateProvider.notifier).state = {
                ...ref.read(tabStateProvider),
                tab.file.uri: isDirty
              };
            },
            canExecute: (ref) {
              final tab = ref
                  .watch(appNotifierProvider)
                  .value
                  ?.currentProject
                  ?.session
                  .currentTab;
              return tab is RecipeTexTab &&
                  (_tabStates[tab.file.uri]?.redoStack.isNotEmpty ?? false);
            }),
      ];

  // --- Parsing Logic (unchanged from original) ---
  RecipeData _parseRecipeContent(String content) {
    final recipeData = RecipeData();

    final recipeMatch = RegExp(
            r'\\recipe\[(.*?)\]{(.*?)}{(.*?)}{(.*?)}{(.*?)}{(.*?)}\n\n',
            dotAll: true)
        .firstMatch(content);

    if (recipeMatch != null) {
      recipeData.image = recipeMatch.group(1) ?? '';
      recipeData.portions =
          _extractCommandContent(recipeMatch.group(3)!, r'portion') ?? '';
      final headerContent = recipeMatch.group(2)!;
      recipeData.title =
          _extractCommandContent(headerContent, r'recipetitle') ?? '';
      final acidRefluxContent = _extractReflux(headerContent);
      recipeData.acidRefluxScore = int.tryParse(acidRefluxContent[0]) ?? 0;
      recipeData.acidRefluxReason = acidRefluxContent[1] ?? '';
      recipeData.prepTime =
          _extractCommandContent(headerContent, r'preptime') ?? '';
      recipeData.cookTime =
          _extractCommandContent(headerContent, r'cooktime') ?? '';
      recipeData.ingredients = _extractListItems(recipeMatch.group(4)!);
      recipeData.instructions =
          _extractInstructionItems(recipeMatch.group(5)!);
      recipeData.notes =
          _extractCommandContent(recipeMatch.group(6)!, r'info') ?? '';
    }
    final imagesMatch = RegExp(r'(% Images[\s\S]*)').firstMatch(content);
    if (imagesMatch != null) {
      recipeData.rawImagesSection = imagesMatch.group(1) ?? '';
    }

    return recipeData;
  }

  List<String> _extractReflux(String latexContent) {
    final regex = RegExp(
      r'\\acidreflux{([^}]+)}\s*%\s*\n\s*{([^}]*)}',
      multiLine: true,
    );
    final match = regex.firstMatch(latexContent);
    if (match == null || match.groupCount < 2) {
      return ['0', ''];
    }
    final score = match.group(1)?.trim() ?? '0';
    final reason = match.group(2)?.trim() ?? '';
    return [score, reason];
  }

  String? _extractCommandContent(String content, String command) {
    final match =
        RegExp('\\\\$command{(.*?)}', dotAll: true).firstMatch(content);
    return match?.group(1);
  }

  List<Ingredient> _extractListItems(String content) {
    return RegExp(r'\\item\s+(.*?)\s*$', multiLine: true)
        .allMatches(content)
        .map((m) => _parseIngredient(m.group(1)!))
        .toList();
  }

  Ingredient _parseIngredient(String line) {
    final match =
        RegExp(r'\\unit(?:\[(.*?)\])?\{(.*?)\}\s*(.*)').firstMatch(line);
    return match != null
        ? Ingredient(
            match.group(1) ?? '', match.group(2) ?? '', match.group(3) ?? '')
        : Ingredient('', '', line);
  }

  List<InstructionStep> _extractInstructionItems(String content) {
    return RegExp(r'\\instruction\{(.*)\}\s*$', multiLine: true)
        .allMatches(content)
        .map((m) => _parseInstruction(m.group(1)!))
        .toList();
  }

  InstructionStep _parseInstruction(String instruction) {
    final titleMatch =
        RegExp(r'\\textbf\{\\large\s*(.*?)\}\s*(.*)').firstMatch(instruction);
    return titleMatch != null
        ? InstructionStep(titleMatch.group(1)!, titleMatch.group(2)!.trim())
        : InstructionStep('', instruction);
  }
}