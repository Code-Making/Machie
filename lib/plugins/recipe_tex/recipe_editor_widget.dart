// lib/plugins/recipe_tex/recipe_editor_widget.dart
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'recipe_tex_models.dart';
import 'recipe_tex_plugin.dart';

class RecipeEditorForm extends ConsumerStatefulWidget {
  final RecipeTexTab tab;
  final RecipeTexPlugin plugin;

  const RecipeEditorForm({super.key, required this.tab, required this.plugin});

  @override
  ConsumerState<RecipeEditorForm> createState() => _RecipeEditorFormState();
}

class _RecipeEditorFormState extends ConsumerState<RecipeEditorForm> {
  late final RecipeData _initialData;
  // Controllers
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
    final recipeData = widget.plugin.getDataForTab(widget.tab);
    if (recipeData == null) {
      // This should not happen if the plugin logic is correct
      _initialData = RecipeData();
    } else {
      _initialData = recipeData;
    }
    _initializeControllers(_initialData);
  }
  
  @override
  void didUpdateWidget(covariant RecipeEditorForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentData = widget.plugin.getDataForTab(widget.tab);
    if (currentData != null && !const DeepCollectionEquality().equals(currentData, _initialData)) {
      _initialData = currentData;
      _syncControllersWithData(currentData);
    }
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
  
  void _syncControllersWithData(RecipeData data) {
    void sync(TextEditingController ctrl, String text) {
      if (ctrl.text != text) ctrl.text = text;
    }
    sync(_titleController, data.title);
    sync(_acidRefluxScoreController, data.acidRefluxScore.toString());
    sync(_acidRefluxReasonController, data.acidRefluxReason);
    sync(_prepTimeController, data.prepTime);
    sync(_cookTimeController, data.cookTime);
    sync(_portionsController, data.portions);
    sync(_notesController, data.notes);
    
    // Sync lists
    _syncListControllers(_ingredientControllers, data.ingredients.length, 3, (i) => data.ingredients[i]);
    _syncListControllers(_instructionControllers, data.instructions.length, 2, (i) => data.instructions[i]);
  }

  void _syncListControllers(List<List<TextEditingController>> controllers, int requiredLength, int sublistLength, Function getModel) {
    // Add missing controllers
    while (controllers.length < requiredLength) {
      controllers.add(List.generate(sublistLength, (_) => TextEditingController()));
    }
    // Remove extra controllers
    while (controllers.length > requiredLength) {
      controllers.removeLast().forEach((c) => c.dispose());
    }
    // Sync text
    for (int i = 0; i < requiredLength; i++) {
        final model = getModel(i);
        if (model is Ingredient) {
            sync(controllers[i][0], model.quantity);
            sync(controllers[i][1], model.unit);
            sync(controllers[i][2], model.name);
        } else if (model is InstructionStep) {
            sync(controllers[i][0], model.title);
            sync(controllers[i][1], model.content);
        }
    }
  }

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

  void _updateData(RecipeData Function(RecipeData) updater) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      widget.plugin.updateDataForTab(widget.tab, updater, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final recipeData = widget.plugin.getDataForTab(widget.tab);
    if (recipeData == null) return const Center(child: Text("Recipe data not available."));

    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.only(left: 16.0, right: 8.0),
        child: ListView(
          children: [
            _buildHeaderSection(),
            const SizedBox(height: 20),
            _buildIngredientsSection(recipeData),
            const SizedBox(height: 20),
            _buildInstructionsSection(recipeData),
            const SizedBox(height: 20),
            _buildNotesSection(),
          ],
        ),
      ),
    );
  }

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

  Widget _buildIngredientsSection(RecipeData data) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: data.ingredients.length,
        itemBuilder: (context, index) => _buildIngredientRow(index),
        onReorder: (oldI, newI) => widget.plugin.reorderIngredient(widget.tab, oldI, newI, ref),
      ),
      ElevatedButton(onPressed: () => widget.plugin.addIngredient(widget.tab, ref), child: const Text('Add Ingredient')),
    ]);
  }

  Widget _buildIngredientRow(int index) {
    final controllers = _ingredientControllers[index];
    return Row(key: ValueKey('ingredient_$index'), children: [
      const Icon(Icons.drag_handle, color: Colors.grey),
      const SizedBox(width: 8),
      SizedBox(width: 50, child: TextFormField(controller: controllers[0], decoration: const InputDecoration(labelText: 'Qty'), onChanged: (v) => _updateData((d) => d..ingredients[index].quantity = v))),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: TextFormField(controller: controllers[1], decoration: const InputDecoration(labelText: 'Unit'), onChanged: (v) => _updateData((d) => d..ingredients[index].unit = v))),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(controller: controllers[2], decoration: const InputDecoration(labelText: 'Ingredient'), onChanged: (v) => _updateData((d) => d..ingredients[index].name = v))),
      IconButton(icon: const Icon(Icons.delete), onPressed: () => widget.plugin.removeIngredient(widget.tab, index, ref)),
    ]);
  }

  Widget _buildInstructionsSection(RecipeData data) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
      ...data.instructions.asMap().entries.map((entry) => _buildInstructionItem(entry.key)),
      ElevatedButton(onPressed: () => widget.plugin.addInstruction(widget.tab, ref), child: const Text('Add Instruction')),
    ]);
  }

  Widget _buildInstructionItem(int index) {
    final controllers = _instructionControllers[index];
    return Column(key: ValueKey('instruction_$index'), children: [
      TextFormField(controller: controllers[0], decoration: InputDecoration(labelText: 'Step ${index + 1} Title', hintText: 'e.g., "Preparation"'), onChanged: (v) => _updateData((d) => d..instructions[index].title = v)),
      TextFormField(controller: controllers[1], decoration: InputDecoration(labelText: 'Step ${index + 1} Details', hintText: 'Describe this step...'), maxLines: null, minLines: 2, onChanged: (v) => _updateData((d) => d..instructions[index].content = v)),
      IconButton(icon: const Icon(Icons.delete), onPressed: () => widget.plugin.removeInstruction(widget.tab, index, ref)),
      const Divider(),
    ]);
  }

  Widget _buildNotesSection() => TextFormField(controller: _notesController, decoration: const InputDecoration(labelText: 'Additional Notes'), maxLines: 3, onChanged: (value) => _updateData((d) => d.copyWith(notes: value)));
}