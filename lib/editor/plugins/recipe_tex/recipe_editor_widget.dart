// =========================================
// UPDATED: lib/editor/plugins/recipe_tex/recipe_editor_widget.dart
// =========================================
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor_tab_models.dart';
import '../../services/editor_service.dart';
import 'recipe_tex_command_context.dart';
import 'recipe_tex_hot_state.dart';
import 'recipe_tex_models.dart';
import 'recipe_tex_plugin.dart';

class RecipeEditorWidget extends EditorWidget {
  const RecipeEditorWidget({
    required GlobalKey<RecipeEditorWidgetState> key,
    required RecipeTexTab tab,
  }) : super(key: key, tab: tab);

  @override
  RecipeEditorWidgetState createState() => RecipeEditorWidgetState();
}

class RecipeEditorWidgetState extends EditorWidgetState<RecipeEditorWidget> {
  // --- STATE ---
  late RecipeData _data;
  late RecipeData _initialData;
  String? _baseContentHash;
  List<RecipeData> _undoStack = [];
  List<RecipeData> _redoStack = [];

  // Controllers remain local to the form UI
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  // ... (all other controllers) ...
  List<List<TextEditingController>> _ingredientControllers = [];
  List<List<TextEditingController>> _instructionControllers = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _baseContentHash = (widget.tab as RecipeTexTab).initialBaseContentHash;

    // Load from hot state if available, otherwise parse from initial content.
    final hotStateData = (widget.tab as RecipeTexTab).hotStateData;
    if (hotStateData != null) {
      _data = hotStateData;
      // The "original" data is the parsed content from disk, to check for dirtiness.
      _initialData = RecipeTexPlugin.parseRecipeContent(
        (widget.tab as RecipeTexTab).initialContent,
      );
    } else {
      _data = RecipeTexPlugin.parseRecipeContent(
        (widget.tab as RecipeTexTab).initialContent,
      );
      _initialData = _data; // Start clean
    }

    _initializeControllers(_data);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkIfDirty();
        syncCommandContext();
      }
    });
  }
  
  // ... (dispose and controller management methods are largely unchanged) ...
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleController.dispose();
    _ingredientControllers.forEach((list) => list.forEach((c) => c.dispose()));
    _instructionControllers.forEach((list) => list.forEach((c) => c.dispose()));
    super.dispose();
  }

  void _initializeControllers(RecipeData data) {
    _titleController = TextEditingController(text: data.title);
    // ... initialize all other controllers ...
    _ingredientControllers = data.ingredients.map((ing) => [
      TextEditingController(text: ing.quantity),
      TextEditingController(text: ing.unit),
      TextEditingController(text: ing.name),
    ]).toList();
    _instructionControllers = data.instructions.map((inst) => [
      TextEditingController(text: inst.title),
      TextEditingController(text: inst.content),
    ]).toList();
  }

  // --- IMPLEMENTATION OF EditorWidgetState ---

  @override
  void syncCommandContext() {
    if (!mounted) return;
    final newContext = RecipeTexCommandContext(
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
    ref.read(commandContextProvider(widget.tab.id).notifier).state = newContext;
  }
  
  @override
  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_data);
    setState(() {
      _data = _undoStack.removeLast();
      _initializeControllers(_data); // Resync UI
    });
    _checkIfDirty();
    syncCommandContext();
  }

  @override
  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_data);
    setState(() {
      _data = _redoStack.removeLast();
      _initializeControllers(_data); // Resync UI
    });
    _checkIfDirty();
    syncCommandContext();
  }

  @override
  Future<EditorContent> getContent() async {
    return EditorContentString(RecipeTexPlugin.generateTexContent(_data));
  }
  
  Future<String> getTexContent() async {
    return RecipeTexPlugin.generateTexContent(_data);
  }

  @override
  void onSaveSuccess(String newHash) {
    if (!mounted) return;
    setState(() {
      _baseContentHash = newHash;
      _initialData = _data; // The new clean state is the current state.
      _undoStack.clear();
      _redoStack.clear();
    });
    ref.read(editorServiceProvider).markCurrentTabClean();
    syncCommandContext();
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    return RecipeTexHotStateDto(
      data: _data,
      baseContentHash: _baseContentHash,
    );
  }

  // --- UI-DRIVEN STATE MUTATION ---

  void _checkIfDirty() {
    final isDirty = !const DeepCollectionEquality().equals(_data, _initialData);
    final editorService = ref.read(editorServiceProvider);
    if (isDirty) {
      editorService.markCurrentTabDirty();
    } else {
      editorService.markCurrentTabClean();
    }
  }

  void _updateData(RecipeData Function(RecipeData) updater) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      
      _undoStack.add(_data);
      if (_undoStack.length > 50) _undoStack.removeAt(0);
      _redoStack.clear();
      
      setState(() {
        _data = updater(_data);
      });
      
      _checkIfDirty();
      syncCommandContext();
    });
  }

  void addIngredient() => _updateData((d) => d.copyWith(ingredients: [...d.ingredients, const Ingredient('', '', '')]));
  void removeIngredient(int index) => _updateData((d) {
    final items = List.of(d.ingredients)..removeAt(index);
    return d.copyWith(ingredients: items);
  });
  void reorderIngredient(int oldIndex, int newIndex) => _updateData((d) {
    final items = List.of(d.ingredients);
    if (oldIndex < newIndex) newIndex--;
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    return d.copyWith(ingredients: items);
  });
  void addInstruction() => _updateData((d) => d.copyWith(instructions: [...d.instructions, const InstructionStep('', '')]));
  void removeInstruction(int index) => _updateData((d) {
    final items = List.of(d.instructions)..removeAt(index);
    return d.copyWith(instructions: items);
  });

  @override
  Widget build(BuildContext context) {
    // UI build logic is mostly the same, but calls to the plugin are replaced with local method calls.
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.only(left: 16.0, right: 8.0),
        child: ListView(
          children: [
            _buildHeaderSection(),
            const SizedBox(height: 20),
            _buildIngredientsSection(),
            const SizedBox(height: 20),
            _buildInstructionsSection(),
            const SizedBox(height: 20),
            _buildNotesSection(),
          ],
        ),
      ),
    );
  }

  // Helper build methods are unchanged, except for how they call mutation methods.
  // Example for add ingredient button:
  // ElevatedButton(onPressed: addIngredient, child: const Text('Add Ingredient')),
  // Example for reorder:
  // onReorder: reorderIngredient,
  // Example for text field:
  // onChanged: (value) => _updateData((d) => d.copyWith(title: value))
  // ... (The rest of the widget build logic is identical but calls local methods) ...
  Widget _buildHeaderSection() { /* ... */ }
  Widget _buildIngredientsSection() { /* ... */ }
  Widget _buildIngredientRow(int index) { /* ... */ }
  Widget _buildInstructionsSection() { /* ... */ }
  Widget _buildInstructionItem(int index) { /* ... */ }
  Widget _buildNotesSection() { /* ... */ }
}