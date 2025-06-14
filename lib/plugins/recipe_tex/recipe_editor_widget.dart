// lib/plugins/recipe_tex/recipe_editor_widget.dart
import 'dart:async';
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
  // Controllers are the "internal state" of this leaf widget
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
    // Get the initial data from the plugin ONCE to populate controllers
    final recipeData = widget.plugin.getDataForTab(widget.tab);
    if (recipeData != null) {
      _initializeControllers(recipeData);
    }
  }

  @override
  void didUpdateWidget(covariant RecipeEditorForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This is the key for making Undo/Redo work.
    // When the plugin forces a rebuild with a new tab instance,
    // we get the latest data and sync our controllers.
    final currentData = widget.plugin.getDataForTab(widget.tab);
    if (currentData != null) {
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

    data.ingredients.asMap().forEach((i, ingredient) {
      _ingredientControllers[i] = [
        TextEditingController(text: ingredient.quantity),
        TextEditingController(text: ingredient.unit),
        TextEditingController(text: ingredient.name),
      ];
    });

    data.instructions.asMap().forEach((i, instruction) {
      _instructionControllers[i] = [
        TextEditingController(text: instruction.title),
        TextEditingController(text: instruction.content),
      ];
    });
  }

  void _syncControllersWithData(RecipeData data) {
    void updateCtrl(TextEditingController ctrl, String text) {
      if (ctrl.text != text) {
        ctrl.text = text;
      }
    }

    updateCtrl(_titleController, data.title);
    updateCtrl(_acidRefluxScoreController, data.acidRefluxScore.toString());
    updateCtrl(_acidRefluxReasonController, data.acidRefluxReason);
    updateCtrl(_prepTimeController, data.prepTime);
    updateCtrl(_cookTimeController, data.cookTime);
    updateCtrl(_portionsController, data.portions);
    updateCtrl(_notesController, data.notes);
    
    // Efficiently sync list controllers
    _syncListControllers(_ingredientControllers, data.ingredients.length, 3);
    _syncListControllers(_instructionControllers, data.instructions.length, 2);

    data.ingredients.asMap().forEach((i, ingredient) {
      updateCtrl(_ingredientControllers[i]![0], ingredient.quantity);
      updateCtrl(_ingredientControllers[i]![1], ingredient.unit);
      updateCtrl(_ingredientControllers[i]![2], ingredient.name);
    });
    data.instructions.asMap().forEach((i, instruction) {
      updateCtrl(_instructionControllers[i]![0], instruction.title);
      updateCtrl(_instructionControllers[i]![1], instruction.content);
    });
  }
  
  void _syncListControllers(Map<int, List<TextEditingController>> controllers, int requiredLength, int sublistLength) {
    final currentKeys = controllers.keys.toList();
    for (int i = 0; i < requiredLength; i++) {
        if (!controllers.containsKey(i)) {
            controllers[i] = List.generate(sublistLength, (_) => TextEditingController());
        }
    }
    for (final key in currentKeys) {
        if (key >= requiredLength) {
            controllers[key]?.forEach((c) => c.dispose());
            controllers.remove(key);
        }
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
    _ingredientControllers.values.forEach((list) => list.forEach((c) => c.dispose()));
    _instructionControllers.values.forEach((list) => list.forEach((c) => c.dispose()));
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We get the data for layout purposes (e.g., list length),
    // but the text comes from the controllers.
    final recipeData = widget.plugin.getDataForTab(widget.tab);
    if (recipeData == null) {
      return const Center(child: Text("Recipe data not available."));
    }
    
    // Ensure controller lists are the right size before building
    _syncListControllers(_ingredientControllers, recipeData.ingredients.length, 3);
    _syncListControllers(_instructionControllers, recipeData.instructions.length, 2);


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
      widget.plugin.updateDataForTab(widget.tab, updater, ref);
    });
  }
  
  // All _build... methods are now simplified. They just use the controllers.

  Widget _buildHeaderSection() {
    return Column(
      children: [
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Recipe Title'),
          onChanged: (value) => _updateData((d) => d.copyWith(title: value)),
        ),
        // ... other header fields ...
         const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _acidRefluxScoreController,
                decoration: const InputDecoration(labelText: 'Acid Reflux Score (0-5)', suffixText: '/5'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) => _updateData((d) => d.copyWith(acidRefluxScore: (int.tryParse(value) ?? 1).clamp(0, 5))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _acidRefluxReasonController,
                decoration: const InputDecoration(labelText: 'Reason for Score'),
                onChanged: (value) => _updateData((d) => d.copyWith(acidRefluxReason: value)),
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
                onChanged: (value) => _updateData((d) => d.copyWith(prepTime: value)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _cookTimeController,
                decoration: const InputDecoration(labelText: 'Cook Time'),
                onChanged: (value) => _updateData((d) => d.copyWith(cookTime: value)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _portionsController,
                decoration: const InputDecoration(labelText: 'Portions'),
                onChanged: (value) => _updateData((d) => d.copyWith(portions: value)),
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
              final items = List.of(d.ingredients);
              final item = items.removeAt(oldIndex);
              items.insert(newIndex, item);
              return d.copyWith(ingredients: items);
            });
          },
          itemBuilder: (context, index) {
            // CORRECTED: The KeyedSubtree contains the ReorderableDelayedDragStartListener, which in turn contains the content.
            return KeyedSubtree(
              key: ValueKey(data.ingredients[index].hashCode),
              child: ReorderableDelayedDragStartListener(
                index: index,
                child: _buildIngredientRow(index),
              ),
            );
          },
        ),
        ElevatedButton(
          onPressed: () => _updateData((d) => d.copyWith(ingredients: [...d.ingredients, Ingredient('', '', '')])),
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
              final items = List.of(d.ingredients);
              items[index] = items[index].copyWith(quantity: value);
              return d.copyWith(ingredients: items);
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
               final items = List.of(d.ingredients);
              items[index] = items[index].copyWith(unit: value);
              return d.copyWith(ingredients: items);
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: controllers[2],
            decoration: const InputDecoration(labelText: 'Ingredient'),
            onChanged: (value) => _updateData((d) {
               final items = List.of(d.ingredients);
              items[index] = items[index].copyWith(name: value);
              return d.copyWith(ingredients: items);
            }),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => _updateData((d) {
             final items = List.of(d.ingredients);
             items.removeAt(index);
             return d.copyWith(ingredients: items);
          }),
        ),
      ],
    );
  }

  Widget _buildInstructionsSection(RecipeData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
        ...data.instructions.asMap().entries.map((entry) => _buildInstructionItem(entry.key)),
        ElevatedButton(
          onPressed: () => _updateData((d) => d.copyWith(instructions: [...d.instructions, InstructionStep('', '')])),
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
          decoration: InputDecoration(labelText: 'Step ${index + 1} Title', hintText: 'e.g., "Preparation"'),
          onChanged: (value) => _updateData((d) {
            final items = List.of(d.instructions);
            items[index] = items[index].copyWith(title: value);
            return d.copyWith(instructions: items);
          }),
        ),
        TextFormField(
          controller: controllers[1],
          decoration: InputDecoration(labelText: 'Step ${index + 1} Details', hintText: 'Describe this step...'),
          maxLines: null,
          minLines: 2,
          onChanged: (value) => _updateData((d) {
            final items = List.of(d.instructions);
            items[index] = items[index].copyWith(content: value);
            return d.copyWith(instructions: items);
          }),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => _updateData((d) {
            final items = List.of(d.instructions);
            items.removeAt(index);
            return d.copyWith(instructions: items);
          }),
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
      onChanged: (value) => _updateData((d) => d.copyWith(notes: value)),
    );
  }
}