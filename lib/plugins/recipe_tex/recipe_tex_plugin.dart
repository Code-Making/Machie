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

class _RecipeTabState {
  RecipeData data;
  final RecipeData originalData;
  List<RecipeData> undoStack;
  List<RecipeData> redoStack;

  _RecipeTabState({
    required this.data,
    required this.originalData,
    this.undoStack = const [],
    this.redoStack = const [],
  });
}

class RecipeTexPlugin implements EditorPlugin {
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
  bool supportsFile(DocumentFile file) => file.name.endsWith('.tex');

  @override
  Future<EditorTab> createTab(DocumentFile file, String content) async {
    final recipeData = _parseRecipeContent(content);
    _tabStates[file.uri] = _RecipeTabState(
      data: recipeData,
      originalData: recipeData.copyWith(),
    );
    return RecipeTexTab(file: file, plugin: this);
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
    return RecipeEditorForm(tab: recipeTab, plugin: this);
  }

  @override
  Widget buildToolbar(WidgetRef ref) => const BottomToolbar();

  @override
  Future<void> dispose() async => _tabStates.clear();

  @override
  void disposeTab(EditorTab tab) => _tabStates.remove(tab.file.uri);

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];

  @override
  void activateTab(EditorTab tab, Ref ref) {}

  @override
  void deactivateTab(EditorTab tab, Ref ref) {}

  RecipeData? getDataForTab(RecipeTexTab tab) => _tabStates[tab.file.uri]?.data;

  void updateDataForTab(RecipeTexTab tab,
      RecipeData Function(RecipeData) updater, WidgetRef ref) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;
    final previousData = state.data;
    final newData = updater(previousData.copyWith());
    state.undoStack.add(previousData);
    state.redoStack.clear();
    state.data = newData;
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

  @override
  List<Command> getCommands() => [
        BaseCommand(
          id: 'copy',
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
          canExecute: (ref) => ref.read(appNotifierProvider).value?.currentProject?.session.currentTab is RecipeTexTab,
        ),
        BaseCommand(
            id: 'save',
            label: 'Save Recipe',
            icon: const Icon(Icons.save),
            defaultPosition: CommandPosition.appBar,
            sourcePlugin: runtimeType.toString(),
            execute: (ref) async {
              final appNotifier = ref.read(appNotifierProvider.notifier);
              final tab = appNotifier.state.value?.currentProject?.session.currentTab as RecipeTexTab?;
              if (tab == null) return;
              final state = _tabStates[tab.file.uri];
              if (state == null) return;

              final content = _generateTexContent(state.data);
              await appNotifier.saveCurrentTab(content: content);

              _tabStates[tab.file.uri] = _RecipeTabState(
                data: state.data.copyWith(),
                originalData: state.data.copyWith(),
                undoStack: [],
                redoStack: [],
              );
              ref.read(rootScaffoldMessengerKeyProvider).currentState?.showSnackBar(
                  const SnackBar(content: Text('Recipe saved.')));
            },
            canExecute: (ref) {
              final tab = ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab;
              return tab != null && (ref.watch(tabStateProvider)[tab.file.uri] ?? false);
            }),
        BaseCommand(
            id: 'undo',
            label: 'Undo',
            icon: const Icon(Icons.undo),
            defaultPosition: CommandPosition.pluginToolbar,
            sourcePlugin: runtimeType.toString(),
            execute: (ref) async {
              final appNotifier = ref.read(appNotifierProvider.notifier);
              final tab = appNotifier.state.value?.currentProject?.session.currentTab as RecipeTexTab?;
              if (tab == null) return;
              final state = _tabStates[tab.file.uri];
              if (state == null || state.undoStack.isEmpty) return;

              final currentData = state.data;
              state.data = state.undoStack.removeLast();
              state.redoStack.add(currentData);
              appNotifier.updateCurrentTab(tab.copyWith());
              
              final isDirty = !const DeepCollectionEquality().equals(state.data, state.originalData);
              ref.read(tabStateProvider.notifier).state = {...ref.read(tabStateProvider), tab.file.uri: isDirty};
            },
            canExecute: (ref) {
              final tab = ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab;
              return tab is RecipeTexTab && (_tabStates[tab.file.uri]?.undoStack.isNotEmpty ?? false);
            }),
        BaseCommand(
            id: 'redo',
            label: 'Redo',
            icon: const Icon(Icons.redo),
            defaultPosition: CommandPosition.pluginToolbar,
            sourcePlugin: runtimeType.toString(),
            execute: (ref) async {
              final appNotifier = ref.read(appNotifierProvider.notifier);
              final tab = appNotifier.state.value?.currentProject?.session.currentTab as RecipeTexTab?;
              if (tab == null) return;
              final state = _tabStates[tab.file.uri];
              if (state == null || state.redoStack.isEmpty) return;
              
              final currentData = state.data;
              state.data = state.redoStack.removeLast();
              state.undoStack.add(currentData);
              appNotifier.updateCurrentTab(tab.copyWith());
              
              final isDirty = !const DeepCollectionEquality().equals(state.data, state.originalData);
              ref.read(tabStateProvider.notifier).state = {...ref.read(tabStateProvider), tab.file.uri: isDirty};
            },
            canExecute: (ref) {
              final tab = ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab;
              return tab is RecipeTexTab && (_tabStates[tab.file.uri]?.redoStack.isNotEmpty ?? false);
            }),
        // NEW COMMAND TO DEMONSTRATE TOOLBAR OVERRIDE
        BaseCommand(
            id: 'special_edit_mode',
            label: 'Special Mode',
            icon: const Icon(Icons.star),
            defaultPosition: CommandPosition.pluginToolbar,
            sourcePlugin: runtimeType.toString(),
            execute: (ref) async {
              final appNotifier = ref.read(appNotifierProvider.notifier);
              final overrideWidget = Container(
                height: 48,
                color: Colors.purple.shade900,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Special Ingredient Mode", style: TextStyle(color: Colors.white)),
                    const SizedBox(width: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade400),
                      child: const Text("Exit Special Mode"),
                      onPressed: () {
                        // Clear the override to restore the default toolbar
                        appNotifier.clearBottomToolbarOverride();
                      },
                    )
                  ],
                ),
              );
              appNotifier.setBottomToolbarOverride(overrideWidget);
            },
            canExecute: (ref) => ref.read(appNotifierProvider).value?.currentProject?.session.currentTab is RecipeTexTab,
        ),
      ];

  RecipeData _parseRecipeContent(String content) {
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
    if (imagesMatch != null) {
      recipeData.rawImagesSection = imagesMatch.group(1) ?? '';
    }
    return recipeData;
  }
  List<String> _extractReflux(String latexContent) {
    final regex = RegExp(r'\\acidreflux{([^}]+)}\s*%\s*\n\s*{([^}]*)}', multiLine: true);
    final match = regex.firstMatch(latexContent);
    if (match == null || match.groupCount < 2) { return ['0', '']; }
    final score = match.group(1)?.trim() ?? '0';
    final reason = match.group(2)?.trim() ?? '';
    return [score, reason];
  }
  String? _extractCommandContent(String content, String command) {
    final match = RegExp('\\\\$command{(.*?)}', dotAll: true).firstMatch(content);
    return match?.group(1);
  }
  List<Ingredient> _extractListItems(String content) {
    return RegExp(r'\\item\s+(.*?)\s*$', multiLine: true).allMatches(content).map((m) => _parseIngredient(m.group(1)!)).toList();
  }
  Ingredient _parseIngredient(String line) {
    final match = RegExp(r'\\unit(?:\[(.*?)\])?\{(.*?)\}\s*(.*)').firstMatch(line);
    return match != null ? Ingredient(match.group(1) ?? '', match.group(2) ?? '', match.group(3) ?? '') : Ingredient('', '', line);
  }
  List<InstructionStep> _extractInstructionItems(String content) {
    return RegExp(r'\\instruction\{(.*)\}\s*$', multiLine: true).allMatches(content).map((m) => _parseInstruction(m.group(1)!)).toList();
  }
  InstructionStep _parseInstruction(String instruction) {
    final titleMatch = RegExp(r'\\textbf\{\\large\s*(.*?)\}\s*(.*)').firstMatch(instruction);
    return titleMatch != null ? InstructionStep(titleMatch.group(1)!, titleMatch.group(2)!.trim()) : InstructionStep('', instruction);
  }
}