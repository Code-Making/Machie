// =========================================
// UPDATED: lib/editor/plugins/recipe_tex/recipe_editor_widget.dart
// =========================================
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  // NO MORE `late RecipeData _data`. Controllers are the source of truth.
  late RecipeData _initialData;
  String? _baseContentHash;
  List<RecipeData> _undoStack = [];
  List<RecipeData> _redoStack = [];

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
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _baseContentHash = (widget.tab as RecipeTexTab).initialBaseContentHash;

    final hotStateData = (widget.tab as RecipeTexTab).hotStateData;
    final initialContent = (widget.tab as RecipeTexTab).initialContent;
    
    // The "original" data is always what's parsed from disk.
    _initialData = RecipeTexPlugin.parseRecipeContent(initialContent);

    // If hot state exists, use it to populate the form, otherwise use the initial data.
    final dataForForm = hotStateData ?? _initialData;
    _initializeControllers(dataForForm);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkIfDirty();
        syncCommandContext();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
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
    _disposeControllers(); // Dispose old ones before creating new ones.

    _titleController = TextEditingController(text: data.title)..addListener(_onFieldChanged);
    _acidRefluxScoreController = TextEditingController(text: data.acidRefluxScore.toString())..addListener(_onFieldChanged);
    _acidRefluxReasonController = TextEditingController(text: data.acidRefluxReason)..addListener(_onFieldChanged);
    _prepTimeController = TextEditingController(text: data.prepTime)..addListener(_onFieldChanged);
    _cookTimeController = TextEditingController(text: data.cookTime)..addListener(_onFieldChanged);
    _portionsController = TextEditingController(text: data.portions)..addListener(_onFieldChanged);
    _notesController = TextEditingController(text: data.notes)..addListener(_onFieldChanged);

    _ingredientControllers = data.ingredients.map((ing) => [
      TextEditingController(text: ing.quantity)..addListener(_onFieldChanged),
      TextEditingController(text: ing.unit)..addListener(_onFieldChanged),
      TextEditingController(text: ing.name)..addListener(_onFieldChanged),
    ]).toList();
    _instructionControllers = data.instructions.map((inst) => [
      TextEditingController(text: inst.title)..addListener(_onFieldChanged),
      TextEditingController(text: inst.content)..addListener(_onFieldChanged),
    ]).toList();
  }
  
  // NEW: The single source of truth for the current state as a RecipeData object.
  RecipeData _buildDataFromControllers() {
    return RecipeData(
      title: _titleController.text,
      acidRefluxScore: (int.tryParse(_acidRefluxScoreController.text) ?? 1).clamp(0, 5),
      acidRefluxReason: _acidRefluxReasonController.text,
      prepTime: _prepTimeController.text,
      cookTime: _cookTimeController.text,
      portions: _portionsController.text,
      image: _initialData.image, // These are not editable in the form
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
    _redoStack.clear();
  }

  @override
  void undo() {
    if (_undoStack.isEmpty) return;
    final currentState = _buildDataFromControllers();
    _redoStack.add(currentState);
    
    final previousState = _undoStack.removeLast();
    setState(() {
      _initializeControllers(previousState);
    });
    
    _checkIfDirty();
    syncCommandContext();
  }

  @override
  void redo() {
    if (_redoStack.isEmpty) return;
    final currentState = _buildDataFromControllers();
    _undoStack.add(currentState);
    
    final nextState = _redoStack.removeLast();
    setState(() {
      _initializeControllers(nextState);
    });

    _checkIfDirty();
    syncCommandContext();
  }

  @override
  Future<EditorContent> getContent() async {
    final currentData = _buildDataFromControllers();
    return EditorContentString(RecipeTexPlugin.generateTexContent(currentData));
  }
  
  Future<String> getTexContent() async {
    final currentData = _buildDataFromControllers();
    return RecipeTexPlugin.generateTexContent(currentData);
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
  
  void _onFieldChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _checkIfDirty();
      syncCommandContext();
    });
  }

  // --- STRUCTURAL CHANGE METHODS ---

  void addIngredient() {
    _pushUndoState();
    setState(() {
      _ingredientControllers.add([
        TextEditingController(text: '')..addListener(_onFieldChanged),
        TextEditingController(text: '')..addListener(_onFieldChanged),
        TextEditingController(text: '')..addListener(_onFieldChanged),
      ]);
    });
    _checkIfDirty();
    syncCommandContext();
  }

  void removeIngredient(int index) {
    _pushUndoState();
    setState(() {
      final removed = _ingredientControllers.removeAt(index);
      removed.forEach((c) => c.dispose());
    });
    _checkIfDirty();
    syncCommandContext();
  }
  
  void reorderIngredient(int oldIndex, int newIndex) {
    _pushUndoState();
    setState(() {
      if (oldIndex < newIndex) newIndex--;
      final item = _ingredientControllers.removeAt(oldIndex);
      _ingredientControllers.insert(newIndex, item);
    });
    _checkIfDirty();
    syncCommandContext();
  }

  void addInstruction() {
    _pushUndoState();
    setState(() {
       _instructionControllers.add([
        TextEditingController(text: '')..addListener(_onFieldChanged),
        TextEditingController(text: '')..addListener(_onFieldChanged),
      ]);
    });
    _checkIfDirty();
    syncCommandContext();
  }

  void removeInstruction(int index) {
    _pushUndoState();
    setState(() {
      final removed = _instructionControllers.removeAt(index);
      removed.forEach((c) => c.dispose());
    });
    _checkIfDirty();
    syncCommandContext();
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
        TextFormField(controller: _titleController, decoration: const InputDecoration(labelText: 'Recipe Title')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _acidRefluxScoreController, decoration: const InputDecoration(labelText: 'Acid Reflux Score (0-5)', suffixText: '/5'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _acidRefluxReasonController, decoration: const InputDecoration(labelText: 'Reason for Score'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _prepTimeController, decoration: const InputDecoration(labelText: 'Prep Time'))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _cookTimeController, decoration: const InputDecoration(labelText: 'Cook Time'))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _portionsController, decoration: const InputDecoration(labelText: 'Portions'))),
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
        itemCount: _ingredientControllers.length, // Use controller list length
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
      SizedBox(width: 50, child: TextFormField(controller: controllers[0], decoration: const InputDecoration(labelText: 'Qty'))),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: TextFormField(controller: controllers[1], decoration: const InputDecoration(labelText: 'Unit'))),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(controller: controllers[2], decoration: const InputDecoration(labelText: 'Ingredient'))),
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
      TextFormField(controller: controllers[0], decoration: InputDecoration(labelText: 'Step ${index + 1} Title', hintText: 'e.g., "Preparation"')),
      TextFormField(controller: controllers[1], decoration: InputDecoration(labelText: 'Step ${index + 1} Details', hintText: 'Describe this step...'), maxLines: null, minLines: 2),
      IconButton(icon: const Icon(Icons.delete), onPressed: () => removeInstruction(index)),
      const Divider(),
    ]);
  }

  Widget _buildNotesSection() => TextFormField(controller: _notesController, decoration: const InputDecoration(labelText: 'Additional Notes'), maxLines: 3);
}