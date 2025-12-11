import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/command/command_widgets.dart';
import 'package:machine/editor/models/editor_command_context.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/plugins/tiled_editor/tiled_editor_plugin.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart';
import 'texture_packer_command_context.dart';
import 'widgets/hierarchy_panel.dart';
import 'widgets/preview_view.dart';
import 'widgets/slicing_app_bar.dart';
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
  TexturePackerMode _mode = TexturePackerMode.slicing;
  bool _isSourceImagesPanelVisible = false;
  bool _isHierarchyPanelVisible = false;
  
  late final TransformationController _transformationController;
  Offset? _dragStart;
  GridRect? _selectionRect;

  @override
  void init() {
    _transformationController = TransformationController();
    ref.listen(texturePackerNotifierProvider(widget.tab.id), (previous, next) {
      if (previous != null) {
        ref.read(editorServiceProvider).markCurrentTabDirty();
      }
      syncCommandContext(); // Sync on any data change
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void onFirstFrameReady() {
    if (mounted && !widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
    syncCommandContext();
  }

// ---------------------------------------------------------------------------
  //region Public Methods for Commands & Callbacks
  // ---------------------------------------------------------------------------

  void setMode(TexturePackerMode newMode) {
    if (_mode == newMode) {
      setState(() => _mode = TexturePackerMode.panZoom);
    } else {
      setState(() => _mode = newMode);
    }
    syncCommandContext();
  }

  void toggleSourceImagesPanel() {
    setState(() {
      _isSourceImagesPanelVisible = !_isSourceImagesPanelVisible;
      if (_isSourceImagesPanelVisible) _isHierarchyPanelVisible = false;
    });
    syncCommandContext();
  }

  void toggleHierarchyPanel() {
    setState(() {
      _isHierarchyPanelVisible = !_isHierarchyPanelVisible;
      if (_isHierarchyPanelVisible) _isSourceImagesPanelVisible = false;
    });
    syncCommandContext();
  }
  
  void cancelSpriteSelection() {
    setState(() {
      _dragStart = null;
      _selectionRect = null;
    });
    syncCommandContext();
  }

  Future<void> confirmSpriteSelection() async {
    // This is the same logic from _onGestureEnd in the previous version
    if (_selectionRect == null) return;
    
    final confirmedRect = _selectionRect!;
    cancelSpriteSelection(); // Clear selection immediately

    final spriteName = await showTextInputDialog(context, title: 'Create New Sprite');
    if (spriteName != null && spriteName.trim().isNotEmpty) {
      final notifier = ref.read(texturePackerNotifierProvider(widget.tab.id).notifier);
      final activeImageIndex = ref.read(activeSourceImageIndexProvider);
      
      final parentId = ref.read(selectedNodeIdProvider);
      
      final newNode = notifier.createNode(
        type: PackerItemType.sprite,
        name: spriteName.trim(),
        parentId: parentId,
      );

      notifier.updateSpriteDefinition(newNode.id, SpriteDefinition(
        sourceImageIndex: activeImageIndex,
        gridRect: confirmedRect,
      ));

      ref.read(selectedNodeIdProvider.notifier).state = newNode.id;
    }
  }

  //endregion

  // ---------------------------------------------------------------------------
  //region Slicing View Callbacks
  // ---------------------------------------------------------------------------

  /// Callback passed to SlicingView for when a gesture starts.
  void onSlicingGestureStart(Offset localPosition, SlicingConfig slicing) {
    if (_mode != TexturePackerMode.slicing) return;

    final invMatrix = Matrix4.copy(_transformationController.value)..invert();
    final positionInImage = MatrixUtils.transformPoint(invMatrix, localPosition);
    
    setState(() {
      _dragStart = positionInImage;
      _selectionRect = _pixelToGridRect(positionInImage, slicing);
    });
    syncCommandContext();
  }

  /// Callback passed to SlicingView for when a gesture updates.
  void onSlicingGestureUpdate(Offset localPosition, SlicingConfig slicing) {
    if (_mode != TexturePackerMode.slicing || _dragStart == null) return;

    final invMatrix = Matrix4.copy(_transformationController.value)..invert();
    final positionInImage = MatrixUtils.transformPoint(invMatrix, localPosition);

    final startRect = _pixelToGridRect(_dragStart!, slicing);
    final endRect = _pixelToGridRect(positionInImage, slicing);

    if (startRect == null || endRect == null) return;
    
    final left = startRect.x < endRect.x ? startRect.x : endRect.x;
    final top = startRect.y < endRect.y ? startRect.y : endRect.y;
    final right = startRect.x > endRect.x ? startRect.x : endRect.x;
    final bottom = startRect.y > endRect.y ? startRect.y : endRect.y;
    
    setState(() {
      _selectionRect = GridRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1);
    });
    syncCommandContext();
  }

  /// Callback passed to SlicingView for when a gesture ends.
  void onSlicingGestureEnd() {
    if (_mode != TexturePackerMode.slicing) return;
    // The selection is not confirmed until the user presses the button
    // in the app bar. So, on gesture end, we do nothing.
  }

  // --- Command Context Sync ---
  @override
  void syncCommandContext() {
    Widget? appBarOverride;
    if (_mode == TexturePackerMode.slicing) {
      appBarOverride = SlicingAppBar(
        onExit: () => setMode(TexturePackerMode.panZoom),
        onConfirm: confirmSpriteSelection,
        onCancel: cancelSpriteSelection,
        hasSelection: _selectionRect != null,
      );
    }

    ref.read(commandContextProvider(widget.tab.id).notifier).state =
        TexturePackerCommandContext(
      mode: _mode,
      isSourceImagesPanelVisible: _isSourceImagesPanelVisible,
      isHierarchyPanelVisible: _isHierarchyPanelVisible,
      hasSelection: _selectionRect != null,
      appBarOverride: appBarOverride,
    );
  }

  GridRect? _pixelToGridRect(Offset p, SlicingConfig s) { /* ... */ }
  void _onGestureStart(Offset p, SlicingConfig s) { /* ... */ }
  void _onGestureUpdate(Offset p, SlicingConfig s) { /* ... */ }

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
  
  Widget _buildMainContent() {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final project = ref.watch(texturePackerNotifierProvider(widget.tab.id));
    // A helper to find a node in the tree
    PackerItemNode? findNode(String id) { /* ... */ return null; }
    
    final node = selectedNodeId != null ? findNode(selectedNodeId) : null;
    final definition = project.definitions[selectedNodeId];

    // Show preview if the selected item is an animation, otherwise show slicer.
    if (node?.type == PackerItemType.animation && definition is AnimationDefinition) {
      return PreviewView(tabId: widget.tab.id);
    }
    
    return _buildSlicingView();
  }

  Widget _buildSlicingView() {
    final activeIndex = ref.watch(activeSourceImageIndexProvider);
    final project = ref.watch(texturePackerNotifierProvider(widget.tab.id));

    if (activeIndex >= project.sourceImages.length) {
      return const Center(child: Text('Select a source image.'));
    }

    final sourceConfig = project.sourceImages[activeIndex];
    
    // Pass all necessary data and callbacks to the SlicingView widget.
    return SlicingView(
      tabId: widget.tab.id,
      transformationController: _transformationController,
      dragSelection: _selectionRect,
      isPanZoomMode: _mode == TexturePackerMode.panZoom,
      onGestureStart: (pos) => onSlicingGestureStart(pos, sourceConfig.slicing),
      onGestureUpdate: (pos) => onSlicingGestureUpdate(pos, sourceConfig.slicing),
      onGestureEnd: onSlicingGestureEnd,
    );
  }
}