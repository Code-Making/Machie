// =========================================
// FINAL CORRECTED FILE: lib/editor/plugins/recipe_tex/recipe_editor_widget.dart
// =========================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';

import '../../models/editor_command_context.dart';
import '../../models/editor_tab_models.dart';
import '../../services/editor_service.dart';
import 'recipe_tex_command_context.dart';
import 'recipe_tex_hot_state.dart';
import 'recipe_tex_models.dart';
import 'recipe_tex_plugin.dart';

import '../../../app/app_notifier.dart'; // Needed for project access

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
  late RecipeData _initialData;
  String? _baseContentHash;
  final List<RecipeData> _undoStack = [];
  final List<RecipeData> _redoStack = [];

  // --- CONTROLLERS & FOCUS NODES ---
  final _formKey = GlobalKey<FormState>();
  // Controllers
  late TextEditingController _titleController;
  late TextEditingController _acidRefluxScoreController;
  late TextEditingController _acidRefluxReasonController;
  late TextEditingController _prepTimeController;
  late TextEditingController _cookTimeController;
  late TextEditingController _portionsController;
  late TextEditingController _notesController;
  List<List<TextEditingController>> _ingredientControllers = [];
  List<List<TextEditingController>> _instructionControllers = [];
  // Focus Nodes
  late FocusNode _titleFocusNode;
  late FocusNode _acidRefluxScoreFocusNode;
  late FocusNode _acidRefluxReasonFocusNode;
  late FocusNode _prepTimeFocusNode;
  late FocusNode _cookTimeFocusNode;
  late FocusNode _portionsFocusNode;
  late FocusNode _notesFocusNode;
  List<List<FocusNode>> _ingredientFocusNodes = [];
  List<List<FocusNode>> _instructionFocusNodes = [];

  bool _isInitialized = false;

  // --- TRANSACTION & DEBOUNCING STATE ---
  RecipeData? _dataOnFocus;
  Timer? _cacheDebounceTimer;
  Timer? _typingUndoDebounce;

  @override
  void init() {
    _baseContentHash = (widget.tab as RecipeTexTab).initialBaseContentHash;
    final hotStateData = (widget.tab as RecipeTexTab).hotStateData;
    final initialContent = (widget.tab as RecipeTexTab).initialContent;

    _initialData = RecipeTexPlugin.parseRecipeContent(initialContent);

    if (hotStateData != null) {
      _undoStack.add(_initialData);
      _initializeControllersAndFocusNodes(hotStateData);
    } else {
      _initializeControllersAndFocusNodes(_initialData);
    }
  }

  @override
  void onFirstFrameReady() {
    if (mounted) {
      _checkIfDirty();
      syncCommandContext();
    }
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  @override
  void dispose() {
    _cacheDebounceTimer?.cancel();
    _typingUndoDebounce?.cancel(); // Dispose the new timer
    _disposeControllersAndFocusNodes();
    super.dispose();
  }

  void _disposeControllersAndFocusNodes() {
    if (!_isInitialized) return;

    _titleController.dispose();
    _titleFocusNode.dispose();
    _acidRefluxScoreController.dispose();
    _acidRefluxScoreFocusNode.dispose();
    _acidRefluxReasonController.dispose();
    _acidRefluxReasonFocusNode.dispose();
    _prepTimeController.dispose();
    _prepTimeFocusNode.dispose();
    _cookTimeController.dispose();
    _cookTimeFocusNode.dispose();
    _portionsController.dispose();
    _portionsFocusNode.dispose();
    _notesController.dispose();
    _notesFocusNode.dispose();
    for (var list in _ingredientControllers) {
      for (var c in list) {
        c.dispose();
      }
    }
    for (var list in _instructionControllers) {
      for (var c in list) {
        c.dispose();
      }
    }
    for (var list in _ingredientFocusNodes) {
      for (var c in list) {
        c.dispose();
      }
    }
    for (var list in _instructionFocusNodes) {
      for (var c in list) {
        c.dispose();
      }
    }
  }

  void _initializeControllersAndFocusNodes(RecipeData data) {
    if (_isInitialized) {
      _disposeControllersAndFocusNodes();
    }

    _titleController = TextEditingController(text: data.title);
    _titleFocusNode =
        FocusNode()
          ..addListener(() => _handleFocusChange(_titleFocusNode.hasFocus));
    _acidRefluxScoreController = TextEditingController(
      text: data.acidRefluxScore.toString(),
    );
    _acidRefluxScoreFocusNode =
        FocusNode()..addListener(
          () => _handleFocusChange(_acidRefluxScoreFocusNode.hasFocus),
        );
    _acidRefluxReasonController = TextEditingController(
      text: data.acidRefluxReason,
    );
    _acidRefluxReasonFocusNode =
        FocusNode()..addListener(
          () => _handleFocusChange(_acidRefluxReasonFocusNode.hasFocus),
        );
    _prepTimeController = TextEditingController(text: data.prepTime);
    _prepTimeFocusNode =
        FocusNode()
          ..addListener(() => _handleFocusChange(_prepTimeFocusNode.hasFocus));
    _cookTimeController = TextEditingController(text: data.cookTime);
    _cookTimeFocusNode =
        FocusNode()
          ..addListener(() => _handleFocusChange(_cookTimeFocusNode.hasFocus));
    _portionsController = TextEditingController(text: data.portions);
    _portionsFocusNode =
        FocusNode()
          ..addListener(() => _handleFocusChange(_portionsFocusNode.hasFocus));
    _notesController = TextEditingController(text: data.notes);
    _notesFocusNode =
        FocusNode()
          ..addListener(() => _handleFocusChange(_notesFocusNode.hasFocus));

    // Use loops to safely create and assign listeners.
    _ingredientControllers = [];
    _ingredientFocusNodes = [];
    for (final ing in data.ingredients) {
      _ingredientControllers.add([
        TextEditingController(text: ing.quantity),
        TextEditingController(text: ing.unit),
        TextEditingController(text: ing.name),
      ]);
      final nodes = [FocusNode(), FocusNode(), FocusNode()];
      nodes[0].addListener(() => _handleFocusChange(nodes[0].hasFocus));
      nodes[1].addListener(() => _handleFocusChange(nodes[1].hasFocus));
      nodes[2].addListener(() => _handleFocusChange(nodes[2].hasFocus));
      _ingredientFocusNodes.add(nodes);
    }

    _instructionControllers = [];
    _instructionFocusNodes = [];
    for (final inst in data.instructions) {
      _instructionControllers.add([
        TextEditingController(text: inst.title),
        TextEditingController(text: inst.content),
      ]);
      final nodes = [FocusNode(), FocusNode()];
      nodes[0].addListener(() => _handleFocusChange(nodes[0].hasFocus));
      nodes[1].addListener(() => _handleFocusChange(nodes[1].hasFocus));
      _instructionFocusNodes.add(nodes);
    }
    _isInitialized = true;
  }

  RecipeData _buildDataFromControllers() {
    return RecipeData(
      title: _titleController.text,
      acidRefluxScore: (int.tryParse(_acidRefluxScoreController.text) ?? 1)
          .clamp(0, 5),
      acidRefluxReason: _acidRefluxReasonController.text,
      prepTime: _prepTimeController.text,
      cookTime: _cookTimeController.text,
      portions: _portionsController.text,
      image: _initialData.image,
      rawImagesSection: _initialData.rawImagesSection,
      ingredients:
          _ingredientControllers
              .map(
                (ctrls) =>
                    Ingredient(ctrls[0].text, ctrls[1].text, ctrls[2].text),
              )
              .toList(),
      instructions:
          _instructionControllers
              .map((ctrls) => InstructionStep(ctrls[0].text, ctrls[1].text))
              .toList(),
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

  void _pushUndoState(RecipeData dataToPush) {
    // FIX #1: Prevent pushing consecutive duplicate states.
    if (_undoStack.isNotEmpty &&
        const DeepCollectionEquality().equals(_undoStack.last, dataToPush)) {
      return;
    }

    _undoStack.add(dataToPush);
    if (_undoStack.length > 30) _undoStack.removeAt(0);
    _redoStack.clear();
    syncCommandContext();
  }

  @override
  void undo() {
    _commitPendingUndo(); // Finalize any "in-flight" text edits first.
    if (_undoStack.isEmpty) return;

    _redoStack.add(_buildDataFromControllers());
    final previousState = _undoStack.removeLast();

    setState(() {
      _initializeControllersAndFocusNodes(previousState);
    });

    _checkIfDirtyAndCache();
    syncCommandContext();
  }

  @override
  void redo() {
    _commitPendingUndo(); // Finalize any "in-flight" text edits first.
    if (_redoStack.isEmpty) return;

    _undoStack.add(_buildDataFromControllers());
    final nextState = _redoStack.removeLast();

    setState(() {
      _initializeControllersAndFocusNodes(nextState);
    });

    _checkIfDirtyAndCache();
    syncCommandContext();
  }

  @override
  Future<EditorContent> getContent() async {
    _commitPendingUndo();
    return EditorContentString(
      RecipeTexPlugin.generateTexContent(_buildDataFromControllers()),
    );
  }

  Future<String> getTexContent() async {
    _commitPendingUndo();
    return RecipeTexPlugin.generateTexContent(_buildDataFromControllers());
  }

  @override
  void onSaveSuccess(String newHash) {
    _commitPendingUndo(); // Ensure state is consistent before marking as clean.
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
    _commitPendingUndo();
    return RecipeTexHotStateDto(
      data: _buildDataFromControllers(),
      baseContentHash: _baseContentHash,
    );
  }

  void _checkIfDirty() {
    final currentData = _buildDataFromControllers();
    final isDirty =
        !const DeepCollectionEquality().equals(currentData, _initialData);
    final editorService = ref.read(editorServiceProvider);
    if (isDirty) {
      editorService.markCurrentTabDirty();
    } else {
      editorService.markCurrentTabClean();
    }
  }
  // --- CONSOLIDATED STATE CHANGE HANDLING ---

  void _handleFocusChange(bool hasFocus) {
    if (hasFocus) {
      // Gained focus: capture the "before" state.
      _dataOnFocus = _buildDataFromControllers();
    } else {
      // Lost focus: compare and push to undo if changed.
      _commitPendingUndo();
    }
  }

  void _commitPendingUndo() {
    _typingUndoDebounce?.cancel();
    if (_dataOnFocus != null) {
      final dataOnBlur = _buildDataFromControllers();
      if (!const DeepCollectionEquality().equals(_dataOnFocus, dataOnBlur)) {
        _pushUndoState(_dataOnFocus!);
      }
      _dataOnFocus = null; // Transaction is complete.
    }
  }

  void _checkIfDirtyAndCache() {
    _cacheDebounceTimer?.cancel();
    _cacheDebounceTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      _checkIfDirty();

      final project = ref.read(appNotifierProvider).value?.currentProject;
      if (project != null) {
        ref
            .read(editorServiceProvider)
            .updateAndCacheDirtyTab(project, widget.tab);
      }
    });
  }

  void _onFieldChanged() {
    _checkIfDirtyAndCache();

    _typingUndoDebounce?.cancel();
    _typingUndoDebounce = Timer(const Duration(milliseconds: 1500), () {
      _commitPendingUndo();
    });
  }

  // --- STRUCTURAL CHANGE METHODS ---

  void addIngredient() {
    _commitPendingUndo();
    _pushUndoState(_buildDataFromControllers());
    setState(() {
      _ingredientControllers.add([
        TextEditingController(),
        TextEditingController(),
        TextEditingController(),
      ]);
      final nodes = [FocusNode(), FocusNode(), FocusNode()];
      nodes[0].addListener(() => _handleFocusChange(nodes[0].hasFocus));
      nodes[1].addListener(() => _handleFocusChange(nodes[1].hasFocus));
      nodes[2].addListener(() => _handleFocusChange(nodes[2].hasFocus));
      _ingredientFocusNodes.add(nodes);
    });
    _checkIfDirtyAndCache();
  }

  void removeIngredient(int index) {
    _commitPendingUndo();
    _pushUndoState(_buildDataFromControllers());
    setState(() {
      _ingredientControllers.removeAt(index).forEach((c) => c.dispose());
      _ingredientFocusNodes.removeAt(index).forEach((c) => c.dispose());
    });
    _checkIfDirtyAndCache();
  }

  void reorderIngredient(int oldIndex, int newIndex) {
    _commitPendingUndo();
    _pushUndoState(_buildDataFromControllers());
    setState(() {
      if (oldIndex < newIndex) newIndex--;
      _ingredientControllers.insert(
        newIndex,
        _ingredientControllers.removeAt(oldIndex),
      );
      _ingredientFocusNodes.insert(
        newIndex,
        _ingredientFocusNodes.removeAt(oldIndex),
      );
    });
    _checkIfDirtyAndCache();
  }

  void addInstruction() {
    _commitPendingUndo();
    _pushUndoState(_buildDataFromControllers());
    setState(() {
      _instructionControllers.add([
        TextEditingController(),
        TextEditingController(),
      ]);
      final nodes = [FocusNode(), FocusNode()];
      nodes[0].addListener(() => _handleFocusChange(nodes[0].hasFocus));
      nodes[1].addListener(() => _handleFocusChange(nodes[1].hasFocus));
      _instructionFocusNodes.add(nodes);
    });
    _checkIfDirtyAndCache();
  }

  void removeInstruction(int index) {
    _commitPendingUndo();
    _pushUndoState(_buildDataFromControllers());
    setState(() {
      _instructionControllers.removeAt(index).forEach((c) => c.dispose());
      _instructionFocusNodes.removeAt(index).forEach((c) => c.dispose());
    });
    _checkIfDirtyAndCache();
  }

  // --- UI BUILDER METHODS ---

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
        TextFormField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          decoration: const InputDecoration(labelText: 'Recipe Title'),
          onChanged: (_) => _onFieldChanged(),
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
                onChanged: (_) => _onFieldChanged(),
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
                onChanged: (_) => _onFieldChanged(),
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
                onChanged: (_) => _onFieldChanged(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _cookTimeController,
                focusNode: _cookTimeFocusNode,
                decoration: const InputDecoration(labelText: 'Cook Time'),
                onChanged: (_) => _onFieldChanged(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _portionsController,
                focusNode: _portionsFocusNode,
                decoration: const InputDecoration(labelText: 'Portions'),
                onChanged: (_) => _onFieldChanged(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIngredientsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _ingredientControllers.length,
          itemBuilder: (context, index) => _buildIngredientRow(index),
          onReorder: reorderIngredient,
        ),
        ElevatedButton(
          onPressed: addIngredient,
          child: const Text('Add Ingredient'),
        ),
      ],
    );
  }

  Widget _buildIngredientRow(int index) {
    final controllers = _ingredientControllers[index];
    final focusNodes = _ingredientFocusNodes[index];
    return Row(
      key: ValueKey('ingredient_$index'),
      children: [
        const Icon(Icons.drag_handle, color: Colors.grey),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: TextFormField(
            controller: controllers[0],
            focusNode: focusNodes[0],
            decoration: const InputDecoration(labelText: 'Qty'),
            onChanged: (_) => _onFieldChanged(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: TextFormField(
            controller: controllers[1],
            focusNode: focusNodes[1],
            decoration: const InputDecoration(labelText: 'Unit'),
            onChanged: (_) => _onFieldChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: controllers[2],
            focusNode: focusNodes[2],
            decoration: const InputDecoration(labelText: 'Ingredient'),
            onChanged: (_) => _onFieldChanged(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => removeIngredient(index),
        ),
      ],
    );
  }

  Widget _buildInstructionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
        ..._instructionControllers.mapIndexed(
          (index, e) => _buildInstructionItem(index),
        ),
        ElevatedButton(
          onPressed: addInstruction,
          child: const Text('Add Instruction'),
        ),
      ],
    );
  }

  Widget _buildInstructionItem(int index) {
    final controllers = _instructionControllers[index];
    final focusNodes = _instructionFocusNodes[index];
    return Column(
      key: ValueKey('instruction_$index'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextFormField(
          controller: controllers[0],
          focusNode: focusNodes[0],
          decoration: InputDecoration(
            labelText: 'Step ${index + 1} Title',
            hintText: 'e.g., "Preparation"',
          ),
          onChanged: (_) => _onFieldChanged(),
        ),
        TextFormField(
          controller: controllers[1],
          focusNode: focusNodes[1],
          decoration: InputDecoration(
            labelText: 'Step ${index + 1} Details',
            hintText: 'Describe this step...',
          ),
          maxLines: null,
          minLines: 2,
          onChanged: (_) => _onFieldChanged(),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => removeInstruction(index),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildNotesSection() => TextFormField(
    controller: _notesController,
    focusNode: _notesFocusNode,
    decoration: const InputDecoration(labelText: 'Additional Notes'),
    maxLines: 3,
    onChanged: (_) => _onFieldChanged(),
  );
}
