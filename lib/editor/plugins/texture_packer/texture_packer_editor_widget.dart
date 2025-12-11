import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'widgets/hierarchy_panel.dart';
import 'widgets/preview_view.dart';
import 'widgets/slicing_view.dart';
import 'widgets/source_images_panel.dart';
import 'texture_packer_editor_models.dart';
import 'texture_packer_models.dart';
import 'texture_packer_notifier.dart';

// Providers for UI state, scoped to the editor instance.
final activeSourceImageIndexProvider = StateProvider.autoDispose<int>((ref) => 0);
final selectedNodeIdProvider = StateProvider.autoDispose<String?>((ref) => null);

class TexturePackerEditorWidget extends EditorWidget {
  @override
  final TexturePackerTab tab;

  const TexturePackerEditorWidget({required super.key, required this.tab})
      : super(tab: tab);

  @override
  TexturePackerEditorWidgetState createState() => TexturePackerEditorWidgetState();
}

class TexturePackerEditorWidgetState extends EditorWidgetState<TexturePackerEditorWidget> {
  bool _showPreview = false;

  @override
  void init() {
    // We now access the notifier via the family provider, so no local instance is needed.
    // The listener for marking the tab dirty can be set up here.
    ref.listen(texturePackerNotifierProvider(widget.tab.id), (previous, next) {
      if (previous != null) { // Avoid marking dirty on initial load
        ref.read(editorServiceProvider).markCurrentTabDirty();
      }
    });
  }

  @override
  void onFirstFrameReady() {
    if (mounted && !widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  @override
  void syncCommandContext() {}
  @override
  void undo() {}
  @override
  void redo() {}
  
  @override
  Future<EditorContent> getContent() async {
    final currentState = ref.read(texturePackerNotifierProvider(widget.tab.id));
    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(currentState.toJson());
    return EditorContentString(jsonString);
  }

  @override
  void onSaveSuccess(String newHash) {}

  @override
  Future<TabHotStateDto?> serializeHotState() async => null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // This is the main layout for the editor.
    // For a more advanced layout, consider a package like `multi_split_view`.
    return Scaffold(
      appBar: AppBar(
        primary: false,
        automaticallyImplyLeading: false,
        title: const Text('Texture Packer'),
        actions: [
          // TODO: Add Export Command Button here
          const SizedBox(width: 16),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showPreview = !_showPreview),
        label: Text(_showPreview ? 'Slicing View' : 'Preview Atlas'),
        icon: Icon(_showPreview ? Icons.grid_on_outlined : Icons.visibility_outlined),
      ),
      body: Row(
        children: [
          // Panel 1: Source Images
          Container(
            width: 250,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: theme.dividerColor)),
            ),
            child: SourceImagesPanel(tabId: widget.tab.id),
          ),

          // Main Content: Slicing or Preview
          Expanded(
            child: _showPreview
                ? PreviewView(tabId: widget.tab.id)
                : SlicingView(tabId: widget.tab.id),
          ),

          // Panel 2: Hierarchy
          Container(
            width: 300,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.dividerColor)),
            ),
            child: HierarchyPanel(tabId: widget.tab.id),
          ),
        ],
      ),
    );
  }
}