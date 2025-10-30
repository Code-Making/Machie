// =========================================
// NEW FILE: lib/editor/plugins/refactor_editor/refactor_editor_widget.dart
// =========================================

import 'package:flutter/material.dart';

import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../editor/editor_tab_models.dart';
import 'refactor_editor_models.dart';

/// A stub for the main UI widget of the Refactor Editor.
class RefactorEditorWidget extends EditorWidget {
  @override
  final RefactorEditorTab tab;

  const RefactorEditorWidget({
    required GlobalKey<RefactorEditorWidgetState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  RefactorEditorWidgetState createState() => RefactorEditorWidgetState();
}

class RefactorEditorWidgetState extends EditorWidgetState<RefactorEditorWidget> {
  @override
  void init() {
    // TODO: Initialize state controller here
  }

  @override
  void onFirstFrameReady() {
    // TODO: Implement
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // This is a placeholder UI. The full implementation will go here.
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.find_replace, size: 48),
          SizedBox(height: 16),
          Text(
            'Refactor Editor UI - Coming Soon!',
            style: TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  @override
  Future<EditorContent> getContent() async {
    // The "content" of this virtual file is its serialized state.
    // TODO: Serialize RefactorSessionState to a JSON string.
    return EditorContentString('{}');
  }

  @override
  void redo() {
    // Not applicable for this editor.
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    // TODO: Get the live state from the StateNotifier and create the DTO.
    return const RefactorEditorHotStateDto(
      searchTerm: '',
      replaceTerm: '',
      isRegex: false,
      isCaseSensitive: false,
    );
  }

  @override
  void syncCommandContext() {
    // Not applicable for this editor.
  }

  @override
  void undo() {
    // Not applicable for this editor.
  }
  
  @override
  void onSaveSuccess(String newHash) {
    // Not applicable as this is a virtual file.
  }
}