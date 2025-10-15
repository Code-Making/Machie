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
  late RecipeData _data;
  late RecipeData _initialData;
  String? _baseContentHash;
  List<RecipeData> _undoStack = [];
  List<RecipeData> _redoStack = [];

  // Controllers remain local to the form UI
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
    _acidRefluxScoreController.dispose();
    _acidRefluxReasonController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _portionsController.dispose();
    _notesController.dispose();
    _ingredientControllers.forEach((list) => list.forEach((c) => c.dispose()));
    _instructionControllers.forEach((list) => list.forEach((c) => c.dispose()));
    super.dispose();
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

  // --- UI BUILDER METHODS ---

  Widget _buildHeaderSection() {
    return Column(
      children: [
        TextFormField(controller: _titleController, decoration: const InputDecoration(labelText: 'Recipe Title'), onChanged: (value) => _updateData((d) => d.copyWith(title: value))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _acidRefluxScoreController, decoration: const InputDecoration(labelText: 'Acid Reflux Score (0-5)', suffixText: '/5'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (value) => _updateData((d) => d.copyWith(acidRefluxScore: (int.tryParse(value) ?? 1).clamp(0, 5))))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _acidRefluxReasonController, decoration: const InputDecoration(labelText: 'Reason for Score'), onChanged: (value) => _updateData((d) => d.copyWith(acidRefluxReason: value)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _prepTimeController, decoration: const InputDecoration(labelText: 'Prep Time'), onChanged: (value) => _updateData((d) => d.copyWith(prepTime: value)))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _cookTimeController, decoration: const InputDecoration(labelText: 'Cook Time'), onChanged: (value) => _updateData((d) => d.copyWith(cookTime: value)))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _portionsController, decoration: const InputDecoration(labelText: 'Portions'), onChanged: (value) => _updateData((d) => d.copyWith(portions: value)))),
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
        itemCount: _data.ingredients.length,
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
      SizedBox(width: 50, child: TextFormField(controller: controllers[0], decoration: const InputDecoration(labelText: 'Qty'), onChanged: (v) => _updateData((d) {
        final newItems = List<Ingredient>.from(d.ingredients);
        newItems[index] = newItems[index].copyWith(quantity: v);
        return d.copyWith(ingredients: newItems);
      }))),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: TextFormField(controller: controllers[1], decoration: const InputDecoration(labelText: 'Unit'), onChanged: (v) => _updateData((d) {
        final newItems = List<Ingredient>.from(d.ingredients);
        newItems[index] = newItems[index].copyWith(unit: v);
        return d.copyWith(ingredients: newItems);
      }))),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(controller: controllers[2], decoration: const InputDecoration(labelText: 'Ingredient'), onChanged: (v) => _updateData((d) {
        final newItems = List<Ingredient>.from(d.ingredients);
        newItems[index] = newItems[index].copyWith(name: v);
        return d.copyWith(ingredients: newItems);
      }))),
      IconButton(icon: const Icon(Icons.delete), onPressed: () => removeIngredient(index)),
    ]);
  }

  Widget _buildInstructionsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
      ..._data.instructions.asMap().entries.map((entry) => _buildInstructionItem(entry.key)),
      ElevatedButton(onPressed: addInstruction, child: const Text('Add Instruction')),
    ]);
  }

  Widget _buildInstructionItem(int index) {
    final controllers = _instructionControllers[index];
    return Column(key: ValueKey('instruction_$index'), crossAxisAlignment: CrossAxisAlignment.end, children: [
      TextFormField(controller: controllers[0], decoration: InputDecoration(labelText: 'Step ${index + 1} Title', hintText: 'e.g., "Preparation"'), onChanged: (v) => _updateData((d) {
        final newItems = List<InstructionStep>.from(d.instructions);
        newItems[index] = newItems[index].copyWith(title: v);
        return d.copyWith(instructions: newItems);
      })),
      TextFormField(controller: controllers[1], decoration: InputDecoration(labelText: 'Step ${index + 1} Details', hintText: 'Describe this step...'), maxLines: null, minLines: 2, onChanged: (v) => _updateData((d) {
        final newItems = List<InstructionStep>.from(d.instructions);
        newItems[index] = newItems[index].copyWith(content: v);
        return d.copyWith(instructions: newItems);
      })),
      IconButton(icon: const Icon(Icons.delete), onPressed: () => removeInstruction(index)),
      const Divider(),
    ]);
  }

  Widget _buildNotesSection() => TextFormField(controller: _notesController, decoration: const InputDecoration(labelText: 'Additional Notes'), maxLines: 3, onChanged: (value) => _updateData((d) => d.copyWith(notes: value)));
}