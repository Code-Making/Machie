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
  late RecipeData _initialData;
  String? _baseContentHash;
  List<RecipeData> _undoStack = [];
  List<RecipeData> _redoStack = [];

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

  // --- TRANSACTION & DEBOUNCING STATE ---
  RecipeData? _dataOnFocus;
  Timer? _cacheDebounceTimer;

  @override
  void initState() {
    super.initState();
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
    _disposeControllersAndFocusNodes();
    super.dispose();
  }

  void _disposeControllersAndFocusNodes() {
    _titleController.dispose(); _titleFocusNode.dispose();
    _acidRefluxScoreController.dispose(); _acidRefluxScoreFocusNode.dispose();
    _acidRefluxReasonController.dispose(); _acidRefluxReasonFocusNode.dispose();
    _prepTimeController.dispose(); _prepTimeFocusNode.dispose();
    _cookTimeController.dispose(); _cookTimeFocusNode.dispose();
    _portionsController.dispose(); _portionsFocusNode.dispose();
    _notesController.dispose(); _notesFocusNode.dispose();
    _ingredientControllers.forEach((list) => list.forEach((c) => c.dispose()));
    _instructionControllers.forEach((list) => list.forEach((c) => c.dispose()));
    _ingredientFocusNodes.forEach((list) => list.forEach((c) => c.dispose()));
    _instructionFocusNodes.forEach((list) => list.forEach((c) => c.dispose()));
  }

  void _initializeControllersAndFocusNodes(RecipeData data) {
    _disposeControllersAndFocusNodes();

    _titleController = TextEditingController(text: data.title);
    _titleFocusNode = FocusNode()..addListener(() => _handleFocusChange(_titleFocusNode.hasFocus));
    // ... Repeat for all header fields ...
    _acidRefluxScoreController = TextEditingController(text: data.acidRefluxScore.toString());
    _acidRefluxScoreFocusNode = FocusNode()..addListener(() => _handleFocusChange(_acidRefluxScoreFocusNode.hasFocus));
    _acidRefluxReasonController = TextEditingController(text: data.acidRefluxReason);
    _acidRefluxReasonFocusNode = FocusNode()..addListener(() => _handleFocusChange(_acidRefluxReasonFocusNode.hasFocus));
    _prepTimeController = TextEditingController(text: data.prepTime);
    _prepTimeFocusNode = FocusNode()..addListener(() => _handleFocusChange(_prepTimeFocusNode.hasFocus));
    _cookTimeController = TextEditingController(text: data.cookTime);
    _cookTimeFocusNode = FocusNode()..addListener(() => _handleFocusChange(_cookTimeFocusNode.hasFocus));
    _portionsController = TextEditingController(text: data.portions);
    _portionsFocusNode = FocusNode()..addListener(() => _handleFocusChange(_portionsFocusNode.hasFocus));
    _notesController = TextEditingController(text: data.notes);
    _notesFocusNode = FocusNode()..addListener(() => _handleFocusChange(_notesFocusNode.hasFocus));

    _ingredientControllers = data.ingredients.map((ing) => [ TextEditingController(text: ing.quantity), TextEditingController(text: ing.unit), TextEditingController(text: ing.name) ]).toList();
    _ingredientFocusNodes = data.ingredients.map((_) => [ FocusNode()..addListener(() => _handleFocusChange(_ingredientFocusNodes.last[0].hasFocus)), FocusNode()..addListener(() => _handleFocusChange(_ingredientFocusNodes.last[1].hasFocus)), FocusNode()..addListener(() => _handleFocusChange(_ingredientFocusNodes.last[2].hasFocus)) ]).toList();
    
    _instructionControllers = data.instructions.map((inst) => [ TextEditingController(text: inst.title), TextEditingController(text: inst.content) ]).toList();
    _instructionFocusNodes = data.instructions.map((_) => [ FocusNode()..addListener(() => _handleFocusChange(_instructionFocusNodes.last[0].hasFocus)), FocusNode()..addListener(() => _handleFocusChange(_instructionFocusNodes.last[1].hasFocus)) ]).toList();
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
    
  void _pushUndoState(RecipeData dataToPush) {
    _undoStack.add(dataToPush);
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
    syncCommandContext();
  }

  @override
  void undo() {
    if (_undoStack.isEmpty) return;
    _commitPendingUndo(); // Commit any active text field before undoing.
    _redoStack.add(_buildDataFromControllers());
    
    final previousState = _undoStack.removeLast();
    setState(() { _initializeControllersAndFocusNodes(previousState); });
    
    _checkIfDirtyAndCache();
    syncCommandContext();
  }

  @override
  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_buildDataFromControllers());
    
    final nextState = _redoStack.removeLast();
    setState(() { _initializeControllersAndFocusNodes(nextState); });

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
        ref.read(editorServiceProvider).updateAndCacheDirtyTab(project, widget.tab);
      }
    });
  }

  void _onFieldChanged() {
    // Keystrokes ONLY trigger caching. Undo is handled by focus changes.
    _checkIfDirtyAndCache();
  }

  // --- STRUCTURAL CHANGE METHODS ---

  void addIngredient() {
    _commitPendingUndo();
    _pushUndoState(_buildDataFromControllers());
    setState(() {
      _ingredientControllers.add([ TextEditingController(), TextEditingController(), TextEditingController() ]);
      _ingredientFocusNodes.add([ FocusNode()..addListener(() => _handleFocusChange(_ingredientFocusNodes.last[0].hasFocus)), FocusNode()..addListener(() => _handleFocusChange(_ingredientFocusNodes.last[1].hasFocus)), FocusNode()..addListener(() => _handleFocusChange(_ingredientFocusNodes.last[2].hasFocus)) ]);
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
      _ingredientControllers.insert(newIndex, _ingredientControllers.removeAt(oldIndex));
      _ingredientFocusNodes.insert(newIndex, _ingredientFocusNodes.removeAt(oldIndex));
    });
    _checkIfDirtyAndCache();
  }

  void addInstruction() {
    _commitPendingUndo();
    _pushUndoState(_buildDataFromControllers());
    setState(() {
       _instructionControllers.add([ TextEditingController(), TextEditingController() ]);
       _instructionFocusNodes.add([ FocusNode()..addListener(() => _handleFocusChange(_instructionFocusNodes.last[0].hasFocus)), FocusNode()..addListener(() => _handleFocusChange(_instructionFocusNodes.last[1].hasFocus)) ]);
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
        TextFormField(controller: _title.$1, focusNode: _title.$2, decoration: const InputDecoration(labelText: 'Recipe Title'), onChanged: (_) => _onFieldChanged()),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _acidRefluxScore.$1, focusNode: _acidRefluxScore.$2, decoration: const InputDecoration(labelText: 'Acid Reflux Score (0-5)', suffixText: '/5'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => _onFieldChanged())),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _acidRefluxReason.$1, focusNode: _acidRefluxReason.$2, decoration: const InputDecoration(labelText: 'Reason for Score'), onChanged: (_) => _onFieldChanged())),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _prepTime.$1, focusNode: _prepTime.$2, decoration: const InputDecoration(labelText: 'Prep Time'), onChanged: (_) => _onFieldChanged())),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _cookTime.$1, focusNode: _cookTime.$2, decoration: const InputDecoration(labelText: 'Cook Time'), onChanged: (_) => _onFieldChanged())),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _portions.$1, focusNode: _portions.$2, decoration: const InputDecoration(labelText: 'Portions'), onChanged: (_) => _onFieldChanged())),
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
        itemCount: _ingredientFields.length,
        itemBuilder: (context, index) => _buildIngredientRow(index),
        onReorder: reorderIngredient,
      ),
      ElevatedButton(onPressed: addIngredient, child: const Text('Add Ingredient')),
    ]);
  }

  Widget _buildIngredientRow(int index) {
    final fields = _ingredientFields[index];
    return Row(key: ValueKey('ingredient_$index'), children: [
      const Icon(Icons.drag_handle, color: Colors.grey),
      const SizedBox(width: 8),
      SizedBox(width: 50, child: TextFormField(controller: fields[0].$1, focusNode: fields[0].$2, decoration: const InputDecoration(labelText: 'Qty'), onChanged: (_) => _onFieldChanged())),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: TextFormField(controller: fields[1].$1, focusNode: fields[1].$2, decoration: const InputDecoration(labelText: 'Unit'), onChanged: (_) => _onFieldChanged())),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(controller: fields[2].$1, focusNode: fields[2].$2, decoration: const InputDecoration(labelText: 'Ingredient'), onChanged: (_) => _onFieldChanged())),
      IconButton(icon: const Icon(Icons.delete), onPressed: () => removeIngredient(index)),
    ]);
  }

  Widget _buildInstructionsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
      ..._instructionFields.mapIndexed((index, e) => _buildInstructionItem(index)),
      ElevatedButton(onPressed: addInstruction, child: const Text('Add Instruction')),
    ]);
  }

  Widget _buildInstructionItem(int index) {
    final fields = _instructionFields[index];
    return Column(key: ValueKey('instruction_$index'), crossAxisAlignment: CrossAxisAlignment.end, children: [
      TextFormField(controller: fields[0].$1, focusNode: fields[0].$2, decoration: InputDecoration(labelText: 'Step ${index + 1} Title', hintText: 'e.g., "Preparation"'), onChanged: (_) => _onFieldChanged()),
      TextFormField(controller: fields[1].$1, focusNode: fields[1].$2, decoration: InputDecoration(labelText: 'Step ${index + 1} Details', hintText: 'Describe this step...'), maxLines: null, minLines: 2, onChanged: (_) => _onFieldChanged()),
      IconButton(icon: const Icon(Icons.delete), onPressed: () => removeInstruction(index)),
      const Divider(),
    ]);
  }

  Widget _buildNotesSection() => TextFormField(controller: _notes.$1, focusNode: _notes.$2, decoration: const InputDecoration(labelText: 'Additional Notes'), maxLines: 3, onChanged: (_) => _onFieldChanged());
}