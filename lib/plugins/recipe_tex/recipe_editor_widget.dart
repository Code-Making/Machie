// lib/plugins/recipe_tex/recipe_editor_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'recipe_tex_models.dart';
import 'recipe_tex_plugin.dart';

class RecipeEditorForm extends ConsumerStatefulWidget {
  final RecipeTexTab tab;
  final RecipeTexPlugin plugin; // NEW: Plugin passed directly

  const RecipeEditorForm({super.key, required this.tab, required this.plugin});

  @override
  ConsumerState<RecipeEditorForm> createState() => _RecipeEditorFormState();
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

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Use the plugin passed via the widget
    final recipeData = widget.plugin.getDataForTab(widget.tab);
    if (recipeData != null) {
      _initializeControllers(recipeData);
    }
  }

  void _initializeControllers(RecipeData data) {
    _titleController = TextEditingController(text: data.title);
    _acidRefluxScoreController =
        TextEditingController(text: data.acidRefluxScore.toString());
    _acidRefluxReasonController =
        TextEditingController(text: data.acidRefluxReason);
    _prepTimeController = TextEditingController(text: data.prepTime);
    _cookTimeController = TextEditingController(text: data.cookTime);
    _portionsController = TextEditingController(text: data.portions);
    _notesController = TextEditingController(text: data.notes);

    for (var i = 0; i < data.ingredients.length; i++) {
      _ingredientControllers[i] = [
        TextEditingController(text: data.ingredients[i].quantity),
        TextEditingController(text: data.ingredients[i].unit),
        TextEditingController(text: data.ingredients[i].name),
      ];
    }
    for (var i = 0; i < data.instructions.length; i++) {
      _instructionControllers[i] = [
        TextEditingController(text: data.instructions[i].title),
        TextEditingController(text: data.instructions[i].content),
      ];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _acidRefluxScoreController.dispose();
    _acidRefluxReasonController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _portionsController.dispose();
    _notesController.dispose();
    _ingredientControllers.values
        .forEach((controllers) => controllers.forEach((c) => c.dispose()));
    _instructionControllers.values
        .forEach((controllers) => controllers.forEach((c) => c.dispose()));
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _syncControllersWithData(RecipeData? data) {
    if (data == null) return;

    void updateController(TextEditingController ctrl, String newText) {
      if (ctrl.text != newText) {
        final selection = ctrl.selection;
        ctrl.text = newText;
        ctrl.selection = selection.copyWith(
            baseOffset: selection.baseOffset.clamp(0, newText.length),
            extentOffset: selection.extentOffset.clamp(0, newText.length));
      }
    }

    updateController(_titleController, data.title);
    updateController(
        _acidRefluxScoreController, data.acidRefluxScore.toString());
    updateController(_acidRefluxReasonController, data.acidRefluxReason);
    updateController(_prepTimeController, data.prepTime);
    updateController(_cookTimeController, data.cookTime);
    updateController(_portionsController, data.portions);
    updateController(_notesController, data.notes);

    // Sync ingredients
    final newIngredientKeys =
        List.generate(data.ingredients.length, (i) => i);
    final oldIngredientKeys = _ingredientControllers.keys.toList();

    for (final key in newIngredientKeys) {
      if (!_ingredientControllers.containsKey(key)) {
        _ingredientControllers[key] = [
          TextEditingController(),
          TextEditingController(),
          TextEditingController()
        ];
      }
      updateController(
          _ingredientControllers[key]![0], data.ingredients[key].quantity);
      updateController(
          _ingredientControllers[key]![1], data.ingredients[key].unit);
      updateController(
          _ingredientControllers[key]![2], data.ingredients[key].name);
    }
    oldIngredientKeys
        .where((k) => !newIngredientKeys.contains(k))
        .forEach((key) {
      _ingredientControllers[key]?.forEach((c) => c.dispose());
      _ingredientControllers.remove(key);
    });

    // Sync instructions
    final newInstructionKeys =
        List.generate(data.instructions.length, (i) => i);
    final oldInstructionKeys = _instructionControllers.keys.toList();

    for (final key in newInstructionKeys) {
      if (!_instructionControllers.containsKey(key)) {
        _instructionControllers[key] = [
          TextEditingController(),
          TextEditingController()
        ];
      }
      updateController(
          _instructionControllers[key]![0], data.instructions[key].title);
      updateController(
          _instructionControllers[key]![1], data.instructions[key].content);
    }
    oldInstructionKeys
        .where((k) => !newInstructionKeys.contains(k))
        .forEach((key) {
      _instructionControllers[key]?.forEach((c) => c.dispose());
      _instructionControllers.remove(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Data now comes from the plugin instance passed in the widget
    final recipeData = widget.plugin.getDataForTab(widget.tab);

    if (recipeData == null) {
      return const Center(child: Text("Recipe data not available."));
    }
    _syncControllersWithData(recipeData);

    return Padding(
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
    );
  }

  void _updateData(RecipeData Function(RecipeData) updater) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      // CORRECTED: Pass the ref to the update method
      widget.plugin.updateDataForTab(widget.tab, updater, ref);
    });
  }

  Widget _buildHeaderSection() {
    return Column(
      children: [
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Recipe Title'),
          onChanged: (value) => _updateData((d) => d..title = value),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _acidRefluxScoreController,
                decoration: const InputDecoration(
                    labelText: 'Acid Reflux Score (0-5)', suffixText: '/5'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) => _updateData((d) =>
                    d..acidRefluxScore = (int.tryParse(value) ?? 1).clamp(0, 5)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _acidRefluxReasonController,
                decoration: const InputDecoration(labelText: 'Reason for Score'),
                onChanged: (value) =>
                    _updateData((d) => d..acidRefluxReason = value),
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
                decoration: const InputDecoration(labelText: 'Prep Time'),
                onChanged: (value) => _updateData((d) => d..prepTime = value),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _cookTimeController,
                decoration: const InputDecoration(labelText: 'Cook Time'),
                onChanged: (value) => _updateData((d) => d..cookTime = value),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _portionsController,
                decoration: const InputDecoration(labelText: 'Portions'),
                onChanged: (value) => _updateData((d) => d..portions = value),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIngredientsSection(RecipeData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: data.ingredients.length,
          onReorder: (oldIndex, newIndex) {
            _updateData((d) {
              if (oldIndex < newIndex) newIndex--;
              final item = d.ingredients.removeAt(oldIndex);
              d.ingredients.insert(newIndex, item);
              return d;
            });
          },
          itemBuilder: (context, index) {
            return KeyedSubtree(
              key: ValueKey('ingredient_${data.ingredients[index].hashCode}'),
              child: ReorderableDelayedDragStartListener(
                index: index,
                child: _buildIngredientRow(index),
              ),
            );
          },
        ),
        ElevatedButton(
          onPressed: () =>
              _updateData((d) => d..ingredients.add(Ingredient('', '', ''))),
          child: const Text('Add Ingredient'),
        ),
      ],
    );
  }

  Widget _buildIngredientRow(int index) {
    final controllers = _ingredientControllers[index]!;
    return Row(
      children: [
        const Icon(Icons.drag_handle, color: Colors.grey),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: TextFormField(
            controller: controllers[0],
            decoration: const InputDecoration(labelText: 'Qty'),
            onChanged: (value) => _updateData((d) {
              d.ingredients[index] =
                  d.ingredients[index].copyWith(quantity: value);
              return d;
            }),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: TextFormField(
            controller: controllers[1],
            decoration: const InputDecoration(labelText: 'Unit'),
            onChanged: (value) => _updateData((d) {
              d.ingredients[index] = d.ingredients[index].copyWith(unit: value);
              return d;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: controllers[2],
            decoration: const InputDecoration(labelText: 'Ingredient'),
            onChanged: (value) => _updateData((d) {
              d.ingredients[index] = d.ingredients[index].copyWith(name: value);
              return d;
            }),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () =>
              _updateData((d) => d..ingredients.removeAt(index)),
        ),
      ],
    );
  }

  Widget _buildInstructionsSection(RecipeData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
        ...data.instructions
            .asMap()
            .entries
            .map((entry) => _buildInstructionItem(entry.key)),
        ElevatedButton(
          onPressed: () => _updateData(
              (d) => d..instructions.add(InstructionStep('', ''))),
          child: const Text('Add Instruction'),
        ),
      ],
    );
  }

  Widget _buildInstructionItem(int index) {
    final controllers = _instructionControllers[index]!;
    return Column(
      key: ValueKey('instruction_$index'),
      children: [
        TextFormField(
          controller: controllers[0],
          decoration: InputDecoration(
              labelText: 'Step ${index + 1} Title',
              hintText: 'e.g., "Preparation"'),
          onChanged: (value) => _updateData((d) {
            d.instructions[index] =
                d.instructions[index].copyWith(title: value);
            return d;
          }),
        ),
        TextFormField(
          controller: controllers[1],
          decoration: InputDecoration(
              labelText: 'Step ${index + 1} Details',
              hintText: 'Describe this step...'),
          maxLines: null,
          minLines: 2,
          onChanged: (value) => _updateData((d) {
            d.instructions[index] =
                d.instructions[index].copyWith(content: value);
            return d;
          }),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () =>
              _updateData((d) => d..instructions.removeAt(index)),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildNotesSection() {
    return TextFormField(
      controller: _notesController,
      decoration: const InputDecoration(labelText: 'Additional Notes'),
      maxLines: 3,
      onChanged: (value) => _updateData((d) => d..notes = value),
    );
  }
}