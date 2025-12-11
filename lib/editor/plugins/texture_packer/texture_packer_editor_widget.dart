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
import '../../../widgets/dialogs/folder_picker_dialog.dart';
import '../../../utils/toast.dart';

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
  
  Future<void> _promptAndAddSourceImage() async {
    // 1. The dialog returns a project-relative path string (e.g., "sprites/player.png").
    // This is the correct format we want to store.
    final newPath = await showDialog<String>(
      context: context,
      builder: (_) => const FileOrFolderPickerDialog(),
    );
    if (newPath != null) {
      if (!newPath.toLowerCase().endsWith('.png')) {
        MachineToast.error('Please select a valid PNG image.');
        return;
      }
      
      // 2. We pass this correct, project-relative path directly to the notifier.
      // The notifier will then save it into the TexturePackerProject state.
      ref.read(texturePackerNotifierProvider(widget.tab.id).notifier).addSourceImage(newPath);
      
      final imageCount = ref.read(texturePackerNotifierProvider(widget.tab.id)).sourceImages.length;
      if (imageCount == 1) {
          ref.read(activeSourceImageIndexProvider.notifier).state = 0;
      }
    }
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
  
  // Add this private method inside your _TexturePackerEditorWidgetState class:

  /// Finds a node by its ID by recursively searching the project tree.
  PackerItemNode? _findNodeById(PackerItemNode node, String id) {
    // Base case: Check if the current node is the one we're looking for.
    if (node.id == id) {
      return node;
    }

    // Recursive step: Search through all children of the current node.
    for (final child in node.children) {
      final found = _findNodeById(child, id);
      // If the node was found in a child's subtree, immediately return it.
      if (found != null) {
        return found;
      }
    }

    // Base case: The node was not found in this branch of the tree.
    return null;
  }


  // ---------------------------------------------------------------------------
  //region Gesture Logic & Callbacks
  // ---------------------------------------------------------------------------

  /// Converts a pixel offset within the source image to a grid cell coordinate.
  /// Returns null if the position is outside a valid cell (e.g., in the margin or padding).
  GridRect? _pixelToGridRect(Offset positionInImage, SlicingConfig slicing) {
    // Ignore clicks in the margin area before the grid starts.
    if (positionInImage.dx < slicing.margin || positionInImage.dy < slicing.margin) {
      return null;
    }

    // Adjust coordinates to be relative to the top-left of the grid area.
    final effectiveX = positionInImage.dx - slicing.margin;
    final effectiveY = positionInImage.dy - slicing.margin;

    // The total size of one cell including its right/bottom padding.
    final cellWidthWithPadding = slicing.tileWidth + slicing.padding;
    final cellHeightWithPadding = slicing.tileHeight + slicing.padding;

    // These must be positive to avoid division by zero.
    if (cellWidthWithPadding <= 0 || cellHeightWithPadding <= 0) {
      return null;
    }

    // Determine the grid cell indices (e.g., column 0, row 1).
    final gridX = (effectiveX / cellWidthWithPadding).floor();
    final gridY = (effectiveY / cellHeightWithPadding).floor();

    // Check if the click was inside the padding area between cells.
    // The modulo operator finds the position *within* a cell+padding block.
    if (effectiveX % cellWidthWithPadding >= slicing.tileWidth) {
      return null; // Clicked in the vertical padding area.
    }
    if (effectiveY % cellHeightWithPadding >= slicing.tileHeight) {
      return null; // Clicked in the horizontal padding area.
    }

    // If all checks pass, we've identified a valid grid cell.
    return GridRect(x: gridX, y: gridY, width: 1, height: 1);
  }
    
  
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
    // The main editor view is a Stack to accommodate the overlay panels (drawers)
    // and the floating command bar.
    return Stack(
      children: [
        // 1. The main content area, which will be either the SlicingView or PreviewView.
        _buildMainContent(),

        // 2. The floating command toolbar in the top-right corner.
        Positioned(
          top: 8,
          right: 8,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              // We re-use the CommandPosition from the Tiled plugin for consistency.
              child: CommandToolbar(position: TiledEditorPlugin.tiledFloatingToolbar),
            ),
          ),
        ),

        // 3. The Source Images Panel, implemented as a drawer sliding from the left.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          top: 0,
          bottom: 0,
          left: _isSourceImagesPanelVisible ? 0 : -251, // Hides just off-screen
          width: 250,
          child: SourceImagesPanel(tabId: widget.tab.id, onAddImage: _promptAndAddSourceImage),
        ),

        // 4. The Hierarchy Panel, implemented as a drawer sliding from the right.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          top: 0,
          bottom: 0,
          right: _isHierarchyPanelVisible ? 0 : -301, // Hides just off-screen
          width: 300,
          child: HierarchyPanel(tabId: widget.tab.id),
        ),
      ],
    );
  }
  
  Widget _buildMainContent() {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final project = ref.watch(texturePackerNotifierProvider(widget.tab.id));

    // **THIS IS THE FIX**: If there are no source images, show the empty state first.
    if (project.sourceImages.isEmpty) {
      return _buildEmptyState();
    }
    
    // Use the correctly implemented helper function to find the node.
    final PackerItemNode? node = selectedNodeId != null 
        ? _findNodeById(project.tree, selectedNodeId) 
        : null;
        
    final definition = project.definitions[selectedNodeId];

    // Logic for view switching:
    // Show the PreviewView only if an ANIMATION is explicitly selected.
    // In all other cases (no selection, folder, or sprite selected), show the SlicingView.
    if (node?.type == PackerItemType.animation && definition is AnimationDefinition) {
      return PreviewView(tabId: widget.tab.id);
    }
    
    return _buildSlicingView();
  }
  
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_search, size: 80, color: theme.textTheme.bodySmall?.color),
          const SizedBox(height: 24),
          Text('Empty Texture Packer Project', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Add a source image to begin slicing sprites.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _promptAndAddSourceImage, // Call the centralized method
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add First Source Image'),
          ),
        ],
      ),
    );
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