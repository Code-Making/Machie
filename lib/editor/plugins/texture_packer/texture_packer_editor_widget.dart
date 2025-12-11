import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'texture_packer_editor_models.dart';
import 'texture_packer_models.dart';
import 'texture_packer_notifier.dart';

/// Provider scoped to the editor widget to hold the TexturePackerNotifier.
final texturePackerNotifierProvider =
    StateNotifierProvider.autoDispose<TexturePackerNotifier, TexturePackerProject>(
  (ref) => throw UnimplementedError(), // Will be overridden in the widget
);

class TexturePackerEditorWidget extends EditorWidget {
  @override
  final TexturePackerTab tab;

  const TexturePackerEditorWidget({required super.key, required this.tab})
      : super(tab: tab);

  @override
  TexturePackerEditorWidgetState createState() => TexturePackerEditorWidgetState();
}

class TexturePackerEditorWidgetState extends EditorWidgetState<TexturePackerEditorWidget> {
  late final TexturePackerNotifier notifier;

  @override
  void init() {
    // Initialize the notifier with the state passed to the tab.
    notifier = TexturePackerNotifier(widget.tab.initialProjectState);

    // Listen for any changes in the state and mark the tab as dirty.
    notifier.addListener((_) {
      ref.read(editorServiceProvider).markCurrentTabDirty();
    });
  }

  @override
  void onFirstFrameReady() {
    if (mounted && !widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }
  
  @override
  void syncCommandContext() {
    // TODO: Implement command context for Texture Packer (e.g., can_delete_node)
  }

  @override
  void undo() {
    // TODO: Implement undo/redo functionality in the notifier.
  }

  @override
  void redo() {
    // TODO: Implement undo/redo functionality in the notifier.
  }
  
  @override
  Future<EditorContent> getContent() async {
    // On save, get the current state from the notifier and serialize it to JSON.
    final currentState = notifier.state;
    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(currentState.toJson());
    return EditorContentString(jsonString);
  }

  @override
  void onSaveSuccess(String newHash) {
    // Base content hash management can be added here if needed.
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    // Hot-state caching is not implemented for this plugin yet.
    return null;
  }
  
  @override
  Widget build(BuildContext context) {
    // Override the provider with the notifier instance for this specific tab.
    return ProviderScope(
      overrides: [
        texturePackerNotifierProvider.overrideWithValue(notifier),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          // The UI will be built in Phase 3. For now, this is a placeholder.
          return const Center(
            child: Text(
              'Texture Packer Editor - UI Coming in Phase 3',
              style: TextStyle(fontSize: 24),
            ),
          );
        },
      ),
    );
  }
}