// =========================================
// FINAL CORRECTED FILE: lib/editor/plugins/recipe_tex/recipe_editor_widget.dart
// =========================================
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart'; // Needed for project access
import '../../editor_tab_models.dart';
import '../editor_command_context.dart';
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
  // The "clean" state loaded from disk. This is our baseline for checking dirtiness.
  late RecipeData _initialData;
  String? _baseContentHash;
  List<RecipeData> _undoStack = [];
  List<RecipeData> _redoStack = [];

  // Controllers are the single source of truth for the UI state.
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _acidRefluxScoreController;
  late TextEditingController _acidRefluxReasonController;
  late TextEditingController _prepTimeController;
  late TextEditingController _cookTimeController;
  late TextEditingController _portionsController;
  late TextEditingController _notesController;
  List<List<TextEditingController>> _ingredientControllers = [];
  List<List<TextEditingController>> _instructionControllers = [];
  
  // Timers for debouncing expensive operations.
  Timer? _cacheDebounceTimer;
  Timer? _undoDebounceTimer;

  @override
  void initState() {
    super.initState();
    _baseContentHash = (widget.tab as RecipeTexTab).initialBaseContentHash;

    final hotStateData = (widget.tab as RecipeTexTab).hotStateData;
    final initialContent = (widget.tab as RecipeTexTab).initialContent;
    
    // 1. The "original" data is always what's parsed from disk.
    _initialData = RecipeTexPlugin.parseRecipeContent(initialContent);

    // 2. If hot state (cached data) exists, handle it correctly.
    if (hotStateData != null) {
      // a. Push the clean, on-disk version to the undo stack.
      //    This allows the user to "undo" back to the saved state.
      _undoStack.add(_initialData);
      // b. The form should be initialized with the cached data.
      _initializeControllers(hotStateData);
    } else {
      // No cache, just initialize the form with the clean data.
      _initializeControllers(_initialData);
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkIfDirty();
        syncCommandContext();
      }
    });
  }

  @override
  void dispose() {
    _cacheDebounceTimer?.cancel();
    _undoDebounceTimer?.cancel();
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    _titleController.dispose();
    _acidRefluxScoreController.dispose();
    _acidRefluxReasonController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _portionsController.dispose();
    _notesController.dispose();
    _ingredientControllers.forEach((list) => list.forEach((c) => c.dispose()));
    _instructionControllers.forEach((list) => list.forEach((c) => c.dispose()));
  }

  void _initializeControllers(RecipeData data) {
    _titleController = TextEditingController(text: data.title);
    _acidRefluxScoreController = TextEditingController(text: data.acidRefluxScore.toString());
    _acidRefluxReasonController = TextEditingController(text: data.acidRefluxReason);
    _prepTimeController = TextEditingController(text: data.prepTime);
    _cookTimeController = TextEditingController(text: data.cookTime);
    _portionsController = TextEditingController(text: data.portions);
    _notesController = TextEditingController(text: data.notes);

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
  
  RecipeData _buildDataFromControllers() {
    return RecipeData(
      title: _titleController.text,
      acidRefluxScore: (int.tryParse(_acidRefluxScoreController.text) ?? 1).clamp(0, 5),
      acidRefluxReason: _acidRefluxReasonController.text,
      prepTime: _prepTimeController.text,
      cookTime: _cookTimeController.text,
      portions: _portionsController.text,
      image: _initialData.image,
      rawImagesSection: _initialData.rawImagesSection,
      ingredients: _ingredientControllers.map((ctrls) => Ingredient(ctrls[0].text, ctrls[1].text, ctrls[2].text)).toList(),
      instructions: _instructionControllers.map((ctrls) => InstructionStep(ctrls[0].text, ctrls[1].text)).toList(),
      notes: _notesController.text,
    );
  }

  @override
  void syncCommandContext() {
    if (!mounted) return;
    final newContext = RecipeTexCommandContext(
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
    ref.read(commandContextProvider(widget.tab.id).notifier).state = newContext;
  }
  
  void _pushUndoState() {
    _undoStack.add(_buildDataFromControllers());
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    // Any new action clears the redo stack.
    _redoStack.clear();
    // After pushing, sync the command context to enable/disable UI buttons.
    syncCommandContext();
  }

  @override
  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_buildDataFromControllers());
    
    final previousState = _undoStack.removeLast();
    setState(() {
      _initializeControllers(previousState);
    });
    
    _checkIfDirtyAndCache();
    syncCommandContext();
  }

  @override
  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_buildDataFromControllers());
    
    final nextState = _redoStack.removeLast();
    setState(() {
      _initializeControllers(nextState);
    });

    _checkIfDirtyAndCache();
    syncCommandContext();
  }

  @override
  Future<EditorContent> getContent() async {
    return EditorContentString(RecipeTexPlugin.generateTexContent(_buildDataFromControllers()));
  }
  
  Future<String> getTexContent() async {
    return RecipeTexPlugin.generateTexContent(_buildDataFromControllers());
  }

  @override
  void onSaveSuccess(String newHash) {
    if (!mounted) return;
    setState(() {
      _baseContentHash = newHash;
      _initialData = _buildDataFromControllers();
      _undoStack.clear();
      _redoStack.clear();
    });
    ref.read(editorServiceProvider).markCurrentTabClean();
    syncCommandContext();
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    return RecipeTexHotStateDto(
      data: _buildDataFromControllers(),
      baseContentHash: _baseContentHash,
    );
  }

  void _checkIfDirty() {
    final currentData = _buildDataFromControllers();
    final isDirty = !const DeepCollectionEquality().equals(currentData, _initialData);
    final editorService = ref.read(editorServiceProvider);
    if (isDirty) {
      editorService.markCurrentTabDirty();
    } else {
      editorService.markCurrentTabClean();
    }
  }
  
  void _checkIfDirtyAndCache() {
    _cacheDebounceTimer?.cancel();
    _cacheDebounceTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      _checkIfDirty();
      
      final project = ref.read(appNotifierProvider).value?.currentProject;
      if (project != null) {
        ref.read(editorServiceProvider).updateAndCacheDirtyTab(project, widget.tab);
      }
    });
  }

  void _onFieldChanged() {
    // This is called on every keystroke. It just triggers the debounced cache.
    _checkIfDirtyAndCache();
  }

  // --- STRUCTURAL CHANGE METHODS ---
  // These now correctly push the "before" state to the undo stack.

  void addIngredient() {
    _pushUndoState();
    setState(() {
      _ingredientControllers.add([
        TextEditingController(), TextEditingController(), TextEditingController()
      ]);
    });
    _checkIfDirtyAndCache();
  }

  void removeIngredient(int index) {
    _pushUndoState();
    setState(() {
      final removed = _ingredientControllers.removeAt(index);
      removed.forEach((c) => c.dispose());
    });
    _checkIfDirtyAndCache();
  }
  
  void reorderIngredient(int oldIndex, int newIndex) {
    _pushUndoState();
    setState(() {
      if (oldIndex < newIndex) newIndex--;
      final item = _ingredientControllers.removeAt(oldIndex);
      _ingredientControllers.insert(newIndex, item);
    });
    _checkIfDirtyAndCache();
  }

  void addInstruction() {
    _pushUndoState();
    setState(() {
       _instructionControllers.add([ TextEditingController(), TextEditingController() ]);
    });
    _checkIfDirtyAndCache();
  }

  void removeInstruction(int index) {
    _pushUndoState();
    setState(() {
      final removed = _instructionControllers.removeAt(index);
      removed.forEach((c) => c.dispose());
    });
    _checkIfDirtyAndCache();
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      children: [
        TextFormField(controller: _titleController, decoration: const InputDecoration(labelText: 'Recipe Title'), onChanged: (_) => _onFieldChanged()),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _acidRefluxScoreController, decoration: const InputDecoration(labelText: 'Acid Reflux Score (0-5)', suffixText: '/5'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => _onFieldChanged())),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _acidRefluxReasonController, decoration: const InputDecoration(labelText: 'Reason for Score'), onChanged: (_) => _onFieldChanged())),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _prepTimeController, decoration: const InputDecoration(labelText: 'Prep Time'), onChanged: (_) => _onFieldChanged())),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _cookTimeController, decoration: const InputDecoration(labelText: 'Cook Time'), onChanged: (_) => _onFieldChanged())),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _portionsController, decoration: const InputDecoration(labelText: 'Portions'), onChanged: (_) => _onFieldChanged())),
        ]),
      ],
    );
  }

  Widget _buildIngredientsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _ingredientControllers.length,
        itemBuilder: (context, index) => _buildIngredientRow(index),
        onReorder: reorderIngredient,
      ),
      ElevatedButton(onPressed: addIngredient, child: const Text('Add Ingredient')),
    ]);
  }

  Widget _buildIngredientRow(int index) {
    final controllers = _ingredientControllers[index];
    return Row(key: ValueKey('ingredient_$index'), children: [
      const Icon(Icons.drag_handle, color: Colors.grey),
      const SizedBox(width: 8),
      SizedBox(width: 50, child: TextFormField(controller: controllers[0], decoration: const InputDecoration(labelText: 'Qty'), onChanged: (_) => _onFieldChanged())),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: TextFormField(controller: controllers[1], decoration: const InputDecoration(labelText: 'Unit'), onChanged: (_) => _onFieldChanged())),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(controller: controllers[2], decoration: const InputDecoration(labelText: 'Ingredient'), onChanged: (_) => _onFieldChanged())),
      IconButton(icon: const Icon(Icons.delete), onPressed: () => removeIngredient(index)),
    ]);
  }

  Widget _buildInstructionsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
      ..._instructionControllers.mapIndexed((index, e) => _buildInstructionItem(index)),
      ElevatedButton(onPressed: addInstruction, child: const Text('Add Instruction')),
    ]);
  }

  Widget _buildInstructionItem(int index) {
    final controllers = _instructionControllers[index];
    return Column(key: ValueKey('instruction_$index'), crossAxisAlignment: CrossAxisAlignment.end, children: [
      TextFormField(controller: controllers[0], decoration: InputDecoration(labelText: 'Step ${index + 1} Title', hintText: 'e.g., "Preparation"'), onChanged: (_) => _onFieldChanged()),
      TextFormField(controller: controllers[1], decoration: InputDecoration(labelText: 'Step ${index + 1} Details', hintText: 'Describe this step...'), maxLines: null, minLines: 2, onChanged: (_) => _onFieldChanged()),
      IconButton(icon: const Icon(Icons.delete), onPressed: () => removeInstruction(index)),
      const Divider(),
    ]);
  }

  Widget _buildNotesSection() => TextFormField(controller: _notesController, decoration: const InputDecoration(labelText: 'Additional Notes'), maxLines: 3, onChanged: (_) => _onFieldChanged());
}