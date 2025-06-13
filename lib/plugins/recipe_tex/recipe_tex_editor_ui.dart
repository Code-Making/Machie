// lib/plugins/recipe_tex/recipe_tex_editor_ui.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/plugins/recipe_tex/recipe_tex_models.dart';

// --------------------
//  Recipe Editor UI
// --------------------
class RecipeEditorForm extends ConsumerStatefulWidget {
  final RecipeData data;

  const RecipeEditorForm({super.key, required this.data});

  @override
  _RecipeEditorFormState createState() => _RecipeEditorFormState();
}

class _RecipeEditorFormState extends ConsumerState<RecipeEditorForm> {
  // Controllers
  late TextEditingController _titleController;
  late TextEditingController _acidRefluxScoreController;
  late TextEditingController _acidRefluxReasonController;
  late TextEditingController _prepTimeController;
  late TextEditingController _cookTimeController;
  late TextEditingController _portionsController;
  late TextEditingController _notesController;
  final Map<int, List<TextEditingController>> _ingredientControllers = {};
  final Map<int, List<TextEditingController>> _instructionControllers = {};

  // Focus Nodes
  late final FocusNode _titleFocusNode;
  late final FocusNode _acidRefluxScoreFocusNode;
  late final FocusNode _acidRefluxReasonFocusNode;
  late final FocusNode _prepTimeFocusNode;
  late final FocusNode _cookTimeFocusNode;
  late final FocusNode _portionsFocusNode;
  late final FocusNode _notesFocusNode;
  final Map<int, List<FocusNode>> _ingredientFocusNodes = {};
  final Map<int, List<FocusNode>> _instructionFocusNodes = {};

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _initializeControllersAndFocusNodes(widget.data);
  }

  void _initializeControllersAndFocusNodes(RecipeData data) {
    // Initialize controllers
    _titleController = TextEditingController(text: data.title);
    _acidRefluxScoreController = TextEditingController(text: data.acidRefluxScore.toString());
    _acidRefluxReasonController = TextEditingController(text: data.acidRefluxReason);
    _prepTimeController = TextEditingController(text: data.prepTime);
    _cookTimeController = TextEditingController(text: data.cookTime);
    _portionsController = TextEditingController(text: data.portions);
    _notesController = TextEditingController(text: data.notes);

    // Initialize focus nodes
    _titleFocusNode = FocusNode();
    _acidRefluxScoreFocusNode = FocusNode();
    _acidRefluxReasonFocusNode = FocusNode();
    _prepTimeFocusNode = FocusNode();
    _cookTimeFocusNode = FocusNode();
    _portionsFocusNode = FocusNode();
    _notesFocusNode = FocusNode();

    // Initialize ingredients
    for (var i = 0; i < data.ingredients.length; i++) {
      _ingredientControllers[i] = [
        TextEditingController(text: data.ingredients[i].quantity),
        TextEditingController(text: data.ingredients[i].unit),
        TextEditingController(text: data.ingredients[i].name),
      ];
      _ingredientFocusNodes[i] = [FocusNode(), FocusNode(), FocusNode()];
    }

    // Initialize instructions
    for (var i = 0; i < data.instructions.length; i++) {
      _instructionControllers[i] = [
        TextEditingController(text: data.instructions[i].title),
        TextEditingController(text: data.instructions[i].content),
      ];
      _instructionFocusNodes[i] = [FocusNode(), FocusNode()];
    }
  }

  @override
  void didUpdateWidget(RecipeEditorForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _syncControllersAndFocusNodes(widget.data);
    }
  }

  void _syncControllersAndFocusNodes(RecipeData newData) {
    // Helper to update controllers
    void updateController(TextEditingController controller, String newValue) {
      if (controller.text != newValue) {
        final selection = controller.selection;
        controller.text = newValue;
        controller.selection = selection.copyWith(
          baseOffset: selection.baseOffset.clamp(0, newValue.length),
          extentOffset: selection.extentOffset.clamp(0, newValue.length),
        );
      }
    }

    updateController(_titleController, newData.title);
    updateController(_acidRefluxScoreController, newData.acidRefluxScore.toString());
    updateController(_acidRefluxReasonController, newData.acidRefluxReason);
    updateController(_prepTimeController, newData.prepTime);
    updateController(_cookTimeController, newData.cookTime);
    updateController(_portionsController, newData.portions);
    updateController(_notesController, newData.notes);

    // Sync ingredients
    for (var i = 0; i < newData.ingredients.length; i++) {
      final ingredient = newData.ingredients[i];
      if (!_ingredientControllers.containsKey(i)) {
        _ingredientControllers[i] = [
          TextEditingController(text: ingredient.quantity),
          TextEditingController(text: ingredient.unit),
          TextEditingController(text: ingredient.name),
        ];
        _ingredientFocusNodes[i] = [FocusNode(), FocusNode(), FocusNode()];
      } else {
        updateController(_ingredientControllers[i]![0], ingredient.quantity);
        updateController(_ingredientControllers[i]![1], ingredient.unit);
        updateController(_ingredientControllers[i]![2], ingredient.name);
      }
    }

    // Remove extra ingredients
    _ingredientControllers.keys.where((i) => i >= newData.ingredients.length).toList()
      ..forEach((i) {
        _ingredientControllers[i]?.forEach((c) => c.dispose());
        _ingredientFocusNodes[i]?.forEach((f) => f.dispose());
        _ingredientControllers.remove(i);
        _ingredientFocusNodes.remove(i);
      });

    // Sync instructions
    for (var i = 0; i < newData.instructions.length; i++) {
      final instruction = newData.instructions[i];
      if (!_instructionControllers.containsKey(i)) {
        _instructionControllers[i] = [
          TextEditingController(text: instruction.title),
          TextEditingController(text: instruction.content),
        ];
        _instructionFocusNodes[i] = [FocusNode(), FocusNode()];
      } else {
        updateController(_instructionControllers[i]![0], instruction.title);
        updateController(_instructionControllers[i]![1], instruction.content);
      }
    }

    // Remove extra instructions
    _instructionControllers.keys.where((i) => i >= newData.instructions.length).toList()
      ..forEach((i) {
        _instructionControllers[i]?.forEach((c) => c.dispose());
        _instructionFocusNodes[i]?.forEach((f) => f.dispose());
        _instructionControllers.remove(i);
        _instructionFocusNodes.remove(i);
      });
  }

  @override
  void dispose() {
    // Dispose controllers
    _titleController.dispose();
    _acidRefluxScoreController.dispose();
    _acidRefluxReasonController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _portionsController.dispose();
    _notesController.dispose();

    // Dispose focus nodes
    _titleFocusNode.dispose();
    _acidRefluxScoreFocusNode.dispose();
    _acidRefluxReasonFocusNode.dispose();
    _prepTimeFocusNode.dispose();
    _cookTimeFocusNode.dispose();
    _portionsFocusNode.dispose();
    _notesFocusNode.dispose();

    // Dispose ingredient controllers and focus nodes
    _ingredientControllers.values.forEach((controllers) => controllers.forEach((c) => c.dispose()));
    _ingredientFocusNodes.values.forEach((nodes) => nodes.forEach((f) => f.dispose()));

    // Dispose instruction controllers and focus nodes
    _instructionControllers.values.forEach((controllers) => controllers.forEach((c) => c.dispose()));
    _instructionFocusNodes.values.forEach((nodes) => nodes.forEach((f) => f.dispose()));

    _debounceTimer?.cancel();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = _getCurrentTab();
    if (currentTab == null) return const SizedBox.shrink();
    
    _syncControllersAndFocusNodes(currentTab.data);
    return Padding(
      padding: const EdgeInsets.only(left:16.0, right:8.0),
      child: ListView(
        children: [
          _buildHeaderSection(currentTab),
          const SizedBox(height: 20),
          _buildIngredientsSection(currentTab),
          const SizedBox(height: 20),
          _buildInstructionsSection(currentTab),
          const SizedBox(height: 20),
          _buildNotesSection(currentTab),
        ],
      ),
    );
  }

  RecipeTexTab? _getCurrentTab() {
    final project = ref.watch(appNotifierProvider).value?.currentProject;
    final tab = project?.session.currentTab;
    return tab is RecipeTexTab ? tab : null;
  }

  Widget _buildHeaderSection(RecipeTexTab tab) {
    return Column(
      children: [
        TextFormField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          decoration: const InputDecoration(labelText: 'Recipe Title'),
          onChanged: (value) => _updateTitle(tab, value),
        ),
              const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _acidRefluxScoreController,
              focusNode: _acidRefluxScoreFocusNode,
              decoration: const InputDecoration(
                labelText: 'Acid Reflux Score (0-5)',
                suffixText: '/5',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) => _updateAcidRefluxScore(tab, value),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _acidRefluxReasonController,
              focusNode: _acidRefluxReasonFocusNode,
              decoration: const InputDecoration(
                labelText: 'Reason for Score',
              ),
              onChanged: (value) => _updateAcidRefluxReason(tab, value),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _prepTimeController,
                focusNode: _prepTimeFocusNode,
                decoration: const InputDecoration(labelText: 'Prep Time'),
                onChanged: (value) => _updatePrepTime(tab, value),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _cookTimeController,
                focusNode: _cookTimeFocusNode,
                decoration: const InputDecoration(labelText: 'Cook Time'),
                onChanged: (value) => _updateCookTime(tab, value),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _portionsController,
                focusNode: _portionsFocusNode,
                decoration: const InputDecoration(labelText: 'Portions'),
                onChanged: (value) => _updatePortions(tab, value),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIngredientsSection(RecipeTexTab tab) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tab.data.ingredients.length,
          onReorder: (oldIndex, newIndex) => _reorderIngredients(tab, oldIndex, newIndex),
          itemBuilder: (context, index) {
            final ingredient = tab.data.ingredients[index];
            return KeyedSubtree(
              key: ValueKey('ingredient_$index'),
              child: ReorderableDelayedDragStartListener(
                index: index,
                child: _buildIngredientRow(tab, index, ingredient),
              ),
            );
          },
        ),
        ElevatedButton(
          onPressed: () => _addIngredient(tab),
          child: const Text('Add Ingredient'),
        ),
      ],
    );
  }

  Widget _buildIngredientRow(RecipeTexTab tab, int index, Ingredient ingredient) {
    final controllers = _ingredientControllers[index]!;
    final focusNodes = _ingredientFocusNodes[index]!;

    return Row(
      key: ValueKey('ingredient_row_$index'),
      children: [
        const Icon(Icons.drag_handle, color: Colors.grey),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: TextFormField(
            controller: controllers[0],
            focusNode: focusNodes[0],
            decoration: const InputDecoration(labelText: 'Qty'),
            onChanged: (value) => _updateIngredientQuantity(tab, index, value),
            textInputAction: TextInputAction.next,
            onEditingComplete: () => focusNodes[1].requestFocus(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: TextFormField(
            controller: controllers[1],
            focusNode: focusNodes[1],
            decoration: const InputDecoration(labelText: 'Unit'),
            onChanged: (value) => _updateIngredientUnit(tab, index, value),
            textInputAction: TextInputAction.next,
            onEditingComplete: () => focusNodes[2].requestFocus(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: controllers[2],
            focusNode: focusNodes[2],
            decoration: const InputDecoration(labelText: 'Ingredient'),
            onChanged: (value) => _updateIngredientName(tab, index, value),
            textInputAction: TextInputAction.done,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => _deleteIngredient(tab, index),
        ),
      ],
    );
  }

  Widget _buildInstructionsSection(RecipeTexTab tab) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
        ...tab.data.instructions.asMap().entries.map((entry) => 
          _buildInstructionItem(tab, entry.key, entry.value)
        ),
        ElevatedButton(
          onPressed: () => _addInstruction(tab),
          child: const Text('Add Instruction'),
        ),
      ],
    );
  }

  Widget _buildInstructionItem(RecipeTexTab tab, int index, InstructionStep instruction) {
    final controllers = _instructionControllers[index]!;
    final focusNodes = _instructionFocusNodes[index]!;

    return Column(
      key: ValueKey('instruction_$index'),  // <-- This is the critical fix
      children: [
        TextFormField(
          controller: controllers[0],
          focusNode: focusNodes[0],
          decoration: InputDecoration(
            labelText: 'Step ${index + 1} Title',
            hintText: 'e.g., "Preparation"'
          ),
          onChanged: (value) => _updateInstructionTitle(tab, index, value),
          textInputAction: TextInputAction.next,
          onEditingComplete: () => focusNodes[1].requestFocus(),
        ),
        TextFormField(
          controller: controllers[1],
          focusNode: focusNodes[1],
          decoration: InputDecoration(
            labelText: 'Step ${index + 1} Details',
            hintText: 'Describe this step...'
          ),
          maxLines: null,
          minLines: 2,
          onChanged: (value) => _updateInstructionContent(tab, index, value),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => _deleteInstruction(tab, index),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildNotesSection(RecipeTexTab tab) {
    return TextFormField(
      controller: _notesController,
      focusNode: _notesFocusNode,
      decoration: const InputDecoration(labelText: 'Additional Notes'),
      maxLines: 3,
      onChanged: (value) => _updateNotes(tab, value),
    );
  }

  // Add/Delete methods with focus management
  void _addIngredient(RecipeTexTab oldTab) {
    final ingredients = List<Ingredient>.from(oldTab.data.ingredients)
      ..add(Ingredient('', '', ''));
    _updateTab(oldTab, (data) => data.copyWith(ingredients: ingredients));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final newIndex = oldTab.data.ingredients.length;
      if (_ingredientFocusNodes.containsKey(newIndex)) {
        FocusScope.of(context).requestFocus(_ingredientFocusNodes[newIndex]?[0]);
      }
    });
  }

  void _deleteIngredient(RecipeTexTab oldTab, int index) {
    _ingredientControllers[index]?.forEach((c) => c.dispose());
    _ingredientFocusNodes[index]?.forEach((f) => f.dispose());
    _ingredientControllers.remove(index);
    _ingredientFocusNodes.remove(index);

    final ingredients = List<Ingredient>.from(oldTab.data.ingredients)..removeAt(index);
    _updateTab(oldTab, (data) => data.copyWith(ingredients: ingredients));
  }

  void _addInstruction(RecipeTexTab oldTab) {
    final instructions = List<InstructionStep>.from(oldTab.data.instructions)
      ..add(InstructionStep('', ''));
    _updateTab(oldTab, (data) => data.copyWith(instructions: instructions));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final newIndex = oldTab.data.instructions.length;
      if (_instructionFocusNodes.containsKey(newIndex)) {
        FocusScope.of(context).requestFocus(_instructionFocusNodes[newIndex]?[0]);
      }
    });
  }

  void _deleteInstruction(RecipeTexTab oldTab, int index) {
    _instructionControllers[index]?.forEach((c) => c.dispose());
    _instructionFocusNodes[index]?.forEach((f) => f.dispose());
    _instructionControllers.remove(index);
    _instructionFocusNodes.remove(index);

    final instructions = List<InstructionStep>.from(oldTab.data.instructions)..removeAt(index);
    _updateTab(oldTab, (data) => data.copyWith(instructions: instructions));
  }

  // Existing update methods remain the same
  void _updateTitle(RecipeTexTab oldTab, String value) => _updateTab(oldTab, (data) => data.copyWith(title: value));
  void _updatePrepTime(RecipeTexTab oldTab, String value) => _updateTab(oldTab, (data) => data.copyWith(prepTime: value));
  void _updateCookTime(RecipeTexTab oldTab, String value) => _updateTab(oldTab, (data) => data.copyWith(cookTime: value));
  void _updatePortions(RecipeTexTab oldTab, String value) => _updateTab(oldTab, (data) => data.copyWith(portions: value));
  void _updateNotes(RecipeTexTab oldTab, String value) => _updateTab(oldTab, (data) => data.copyWith(notes: value));
  void _updateAcidRefluxScore(RecipeTexTab oldTab, String value) {
      final score = int.tryParse(value) ?? oldTab.data.acidRefluxScore;
      _updateTab(oldTab, (data) => data.copyWith(acidRefluxScore: score.clamp(0, 5)));
   }
    
  void _updateAcidRefluxReason(RecipeTexTab oldTab, String value) {
      _updateTab(oldTab, (data) => data.copyWith(acidRefluxReason: value));
  }
  void _reorderIngredients(RecipeTexTab oldTab, int oldIndex, int newIndex) {
    final ingredients = List<Ingredient>.from(oldTab.data.ingredients);
    if (oldIndex < newIndex) newIndex--;
    final item = ingredients.removeAt(oldIndex);
    ingredients.insert(newIndex, item);
    _updateTab(oldTab, (data) => data.copyWith(ingredients: ingredients));
  }

  void _updateIngredientQuantity(RecipeTexTab oldTab, int index, String value) {
    final ingredients = List<Ingredient>.from(oldTab.data.ingredients);
    ingredients[index] = ingredients[index].copyWith(quantity: value);
    _updateTab(oldTab, (data) => data.copyWith(ingredients: ingredients));
  }

  void _updateIngredientUnit(RecipeTexTab oldTab, int index, String value) {
    final ingredients = List<Ingredient>.from(oldTab.data.ingredients);
    ingredients[index] = ingredients[index].copyWith(unit: value);
    _updateTab(oldTab, (data) => data.copyWith(ingredients: ingredients));
  }

  void _updateIngredientName(RecipeTexTab oldTab, int index, String value) {
    final ingredients = List<Ingredient>.from(oldTab.data.ingredients);
    ingredients[index] = ingredients[index].copyWith(name: value);
    _updateTab(oldTab, (data) => data.copyWith(ingredients: ingredients));
  }

  void _updateInstructionTitle(RecipeTexTab oldTab, int index, String value) {
    final instructions = List<InstructionStep>.from(oldTab.data.instructions);
    instructions[index] = instructions[index].copyWith(title: value);
    _updateTab(oldTab, (data) => data.copyWith(instructions: instructions));
  }

  void _updateInstructionContent(RecipeTexTab oldTab, int index, String value) {
    final instructions = List<InstructionStep>.from(oldTab.data.instructions);
    instructions[index] = instructions[index].copyWith(content: value);
    _updateTab(oldTab, (data) => data.copyWith(instructions: instructions));
  }

  void _updateTab(RecipeTexTab oldTab, RecipeData Function(RecipeData) updater) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
        final previousData = oldTab.data;
        final newData = updater(previousData.copyWith());
    
        final newTab = oldTab.copyWith(
          data: newData,
          undoStack: [...oldTab.undoStack, previousData],
          redoStack: [],
          isDirty: newData != oldTab.originalData,
        );
    
      ref.read(appNotifierProvider.notifier).updateCurrentTab(newTab);
    });
  }
}