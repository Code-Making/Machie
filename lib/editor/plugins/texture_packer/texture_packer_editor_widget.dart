import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math';
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
import 'package:collection/collection.dart'; // Import for SetEquality
import 'texture_packer_plugin.dart';
import '../../../project/project_settings_notifier.dart';
import 'texture_packer_settings.dart';
import 'widgets/preview_app_bar.dart';
import 'widgets/texture_packer_file_dialog.dart'; // Import the new dialog
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:path/path.dart' as p;

// Providers for UI state, scoped to the editor instance.
final activeSourceImageIdProvider = StateProvider.autoDispose<String?>((ref) => null);
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
  
  late final TexturePackerNotifier _notifier;
  TexturePackerNotifier get notifier => _notifier;
  Set<String> _requiredAssetUris = const {};

  TexturePackerMode _mode = TexturePackerMode.slicing;
  bool _isSourceImagesPanelVisible = false;
  bool _isHierarchyPanelVisible = false;
  
  late final TransformationController _transformationController;
  Offset? _dragStart;
  GridRect? _selectionRect;

  @override
  void init() {
    _transformationController = TransformationController();
    _notifier = TexturePackerNotifier(widget.tab.initialProjectState);
    _notifier.addListener(_onNotifierUpdate);
  }
  
  void _onNotifierUpdate() {
    ref.read(editorServiceProvider).markCurrentTabDirty();
    syncCommandContext();
    // --- ASSET LOADING REFACTOR ---
    // When the notifier's data changes (e.g., an image is added),
    // we must re-evaluate the required assets.
    _updateAndLoadAssetUris();
    // --- END REFACTOR ---
    setState(() {});
  }

  @override
  void dispose() {
    _notifier.removeListener(_onNotifierUpdate);
    _notifier.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void onFirstFrameReady() {
    if (mounted && !widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
    // --- ASSET LOADING REFACTOR ---
    // Initial load of assets required by the project file.
    _updateAndLoadAssetUris();
    // --- END REFACTOR ---
    syncCommandContext();
  }

  // --- ASSET LOADING REFACTOR ---
  /// Collects all source image paths from the project and tells the
  /// assetMapProvider to load them.
  
  SourceImageConfig? _findSourceConfig(String id) {
    SourceImageConfig? traverse(SourceImageNode node) {
      if (node.id == id && node.type == SourceNodeType.image) return node.content;
      for (final child in node.children) {
        final res = traverse(child);
        if (res != null) return res;
      }
      return null;
    }
    return traverse(_notifier.project.sourceImagesRoot);
  }
  
  void _updateAndLoadAssetUris() {
    if (!mounted) return;

    final uris = <String>{};
    void collectPaths(SourceImageNode node) {
      if (node.type == SourceNodeType.image && node.content != null) {
        if (node.content!.path.isNotEmpty) {
          uris.add(node.content!.path);
        }
      }
      for (final child in node.children) collectPaths(child);
    }
    collectPaths(_notifier.project.sourceImagesRoot);

    if (!const SetEquality().equals(uris, _requiredAssetUris)) {
      _requiredAssetUris = uris;
      ref.read(assetMapProvider(widget.tab.id).notifier).updateUris(uris);
    }
  }
  // --- END REFACTOR ---

// ---------------------------------------------------------------------------
  //region Public Methods for Commands & Callbacks
  // ---------------------------------------------------------------------------

  void setMode(TexturePackerMode newMode) {
    if (_mode == newMode) {
      // If toggling the active mode, revert to PanZoom (default state)
      // Exception: If we are in preview, toggling it off goes back to PanZoom
      setState(() => _mode = TexturePackerMode.panZoom);
    } else {
      setState(() => _mode = newMode);
    }
    syncCommandContext();
  }
  
  // Call this whenever selectedNodeIdProvider changes via the hierarchy
  void _syncActiveImageToSelection() {
    final selectedId = ref.read(selectedNodeIdProvider);
    if (selectedId == null) return;

    final definition = _notifier.project.definitions[selectedId];
    if (definition is SpriteDefinition) {
      // If a sprite is selected, automatically switch the view to that image
      ref.read(activeSourceImageIndexProvider.notifier).state = definition.sourceImageIndex;
    }
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



  //endregion

  // ---------------------------------------------------------------------------
  //region Slicing View Callbacks
  // ---------------------------------------------------------------------------



  // Helper to convert an image pixel coordinate to a grid coordinate.
  // Returns point(gridX, gridY) or null if invalid.
  Point<int>? _pixelToGridPoint(Offset positionInImage, SlicingConfig slicing) {
    if (positionInImage.dx < slicing.margin || positionInImage.dy < slicing.margin) {
      return null;
    }
    
    final effectiveX = positionInImage.dx - slicing.margin;
    final effectiveY = positionInImage.dy - slicing.margin;
    final cellWidthWithPadding = slicing.tileWidth + slicing.padding;
    final cellHeightWithPadding = slicing.tileHeight + slicing.padding;

    if (cellWidthWithPadding <= 0 || cellHeightWithPadding <= 0) return null;

    final gridX = (effectiveX / cellWidthWithPadding).floor();
    final gridY = (effectiveY / cellHeightWithPadding).floor();

    // Check if we are inside the tile or in the gutter/padding
    final offsetInCellX = effectiveX % cellWidthWithPadding;
    final offsetInCellY = effectiveY % cellHeightWithPadding;

    if (offsetInCellX >= slicing.tileWidth || offsetInCellY >= slicing.tileHeight) {
      return null; // In padding area
    }

    return Point(gridX, gridY);
  }

  void onSlicingGestureStart(Offset localPosition, SlicingConfig slicing) {
    if (_mode != TexturePackerMode.slicing) return;

    final invMatrix = Matrix4.copy(_transformationController.value)..invert();
    final positionInImage = MatrixUtils.transformPoint(invMatrix, localPosition);
    
    setState(() {
      _dragStart = positionInImage;
      final point = _pixelToGridPoint(positionInImage, slicing);
      if (point != null) {
        _selectionRect = GridRect(x: point.x, y: point.y, width: 1, height: 1);
      } else {
        _selectionRect = null;
      }
    });
    syncCommandContext();
  }

  void onSlicingGestureUpdate(Offset localPosition, SlicingConfig slicing) {
    if (_mode != TexturePackerMode.slicing || _dragStart == null) return;

    final invMatrix = Matrix4.copy(_transformationController.value)..invert();
    final positionInImage = MatrixUtils.transformPoint(invMatrix, localPosition);

    final startPoint = _pixelToGridPoint(_dragStart!, slicing);
    final endPoint = _pixelToGridPoint(positionInImage, slicing);

    if (startPoint == null || endPoint == null) return;
    
    // Calculate bounds of selection
    final left = min(startPoint.x, endPoint.x);
    final top = min(startPoint.y, endPoint.y);
    final right = max(startPoint.x, endPoint.x);
    final bottom = max(startPoint.y, endPoint.y);
    
    setState(() {
      _selectionRect = GridRect(
        x: left, 
        y: top, 
        width: right - left + 1, 
        height: bottom - top + 1
      );
    });
    // No need to sync context on every drag frame usually, but if commands depend on bounds:
    // syncCommandContext(); 
  }

  Future<void> confirmSpriteSelection() async {
    if (_selectionRect == null) return;
    final rect = _selectionRect!;
    final bool isMulti = rect.width > 1 || rect.height > 1;

    if (!isMulti) {
      await _createSingleSprite(rect);
    } else {
      await _handleMultiSelection(rect);
    }
    cancelSpriteSelection();
  }

  Future<void> _createSingleSprite(GridRect rect) async {
    final spriteName = await showTextInputDialog(context, title: 'Create New Sprite');
    if (spriteName != null && spriteName.trim().isNotEmpty) {
      final activeImageId = ref.read(activeSourceImageIdProvider);
      if (activeImageId == null) return;

      final parentId = ref.read(selectedNodeIdProvider);
      
      final newNode = _notifier.createNode(
        type: PackerItemType.sprite,
        name: spriteName.trim(),
        parentId: parentId, // Create inside selected folder/anim if valid, or root
      );

      _notifier.updateSpriteDefinition(newNode.id, SpriteDefinition(
        sourceImageId: activeImageId,
        gridRect: rect,
      ));
      
      ref.read(selectedNodeIdProvider.notifier).state = newNode.id;
    }
  }

  Future<void> _handleMultiSelection(GridRect rect) async {
    const optionAnim = 'Create Animation';
    const optionBatch = 'Batch Sprites';
    const optionSingle = 'Single Sprite (Merged)';

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Multi-Selection Action'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, optionAnim),
            child: const ListTile(
              leading: Icon(Icons.movie_creation_outlined),
              title: Text(optionAnim),
              subtitle: Text('Create frames nested inside an animation.'),
            ),
          ),
          // ... Batch and Single options remain same ...
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, optionBatch),
            child: const ListTile(
              leading: Icon(Icons.copy_all_outlined),
              title: Text(optionBatch),
              subtitle: Text('Create independent sprites for each selected tile.'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, optionSingle),
            child: const ListTile(
              leading: Icon(Icons.crop_free),
              title: Text(optionSingle),
              subtitle: Text('Create one sprite covering the entire area.'),
            ),
          ),
        ],
      ),
    );

    if (choice == null) return;

    if (choice == optionSingle) {
      await _createSingleSprite(rect);
      return;
    }

    final baseName = await showTextInputDialog(context, title: 'Base Name');
    if (baseName == null || baseName.trim().isEmpty) return;
    
    final activeImageId = ref.read(activeSourceImageIdProvider);
    if (activeImageId == null) return;

    final parentId = ref.read(selectedNodeIdProvider); 

    // Generate definitions
    final definitions = <SpriteDefinition>[];
    final names = <String>[];
    
    int counter = 0;
    for (int y = 0; y < rect.height; y++) {
      for (int x = 0; x < rect.width; x++) {
        final tileRect = GridRect(x: rect.x + x, y: rect.y + y, width: 1, height: 1);
        definitions.add(SpriteDefinition(
          sourceImageId: activeImageId, 
          gridRect: tileRect,
        ));
        names.add('${baseName.trim()}_$counter');
        counter++;
      }
    }

    if (choice == optionBatch) {
      _notifier.createBatchSprites(
        names: names,
        definitions: definitions,
        parentId: parentId,
      );
    } else if (choice == optionAnim) {
      // 1. Create the sprites first (temp)
      final nodes = _notifier.createBatchSprites(
        names: names,
        definitions: definitions,
        parentId: parentId, // These will be moved into the animation shortly
      );
      
      final settings = ref.read(effectiveSettingsProvider
        .select((s) => s.pluginSettings[TexturePackerSettings] as TexturePackerSettings?));
      
      // 2. Create animation and nest the sprites
      _notifier.createAnimationFromExistingSprites(
        name: baseName.trim(),
        frameNodeIds: nodes.map((n) => n.id).toList(),
        parentId: parentId,
        speed: settings?.defaultAnimationSpeed ?? 10.0,
      );
    }
  }

  void onSlicingGestureEnd() {
    if (_mode != TexturePackerMode.slicing) return;
  }
  
  Future<void> _promptAndAddSourceImages() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null) return;

    // 1. Show the custom picker
    final result = await showDialog<TexturePackerImportResult>(
      context: context,
      builder: (_) => TexturePackerFilePickerDialog(projectRootUri: project.rootUri),
    );

    if (result == null || result.files.isEmpty) return;

    final repo = ref.read(projectRepositoryProvider)!;
    
    // Determine the parent folder for new Sprites/Animations (from selection)
    final outputParentId = ref.read(selectedNodeIdProvider); 

    // 2. Ask for mode if "Import as Sprites" is checked AND multiple files
    String mode = 'batch'; 
    String? baseName;
    
    if (result.asSprites && result.files.length > 1) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Import Mode'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'batch'),
              child: const ListTile(
                leading: Icon(Icons.copy_all),
                title: Text('Batch Sprites'),
                subtitle: Text('Create individual sprites for each image.'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'anim'),
              child: const ListTile(
                leading: Icon(Icons.movie_creation),
                title: Text('Animation'),
                subtitle: Text('Create one animation using images as frames.'),
              ),
            ),
          ],
        ),
      );
      if (choice == null) return; // Cancelled
      mode = choice;
      
      if (mode == 'anim') {
        baseName = await showTextInputDialog(context, title: 'Animation Name');
        if (baseName == null || baseName.trim().isEmpty) return;
      }
    }

    // 3. Process Files
    final List<String> createdSpriteNodeIds = [];
    final List<String> createdNames = [];

    // Auto-create a source folder if importing multiple images to keep source tree clean?
    // Let's keep it simple: Add to root source.
    
    for (final file in result.files) {
      // a. Resolve path
      final relativePath = repo.fileHandler.getPathForDisplay(
        file.uri, 
        relativeTo: project.rootUri
      );

      // b. Determine Config (Load dimensions if needed)
      SlicingConfig config = const SlicingConfig();
      
      if (result.asSprites) {
        try {
          // Eagerly load the asset to get dimensions for the SlicingConfig
          final assetData = await ref.read(assetDataProvider(relativePath).future);
          
          if (assetData is ImageAssetData) {
            config = SlicingConfig(
              tileWidth: assetData.image.width,
              tileHeight: assetData.image.height,
              margin: 0,
              padding: 0,
            );
          }
        } catch (e) {
          MachineToast.error('Failed to load dimensions for ${file.name}');
          // Continue with default config, user can fix later
        }
      }

      // c. Add Source Image to Project Tree
      final sourceNode = _notifier.addSourceNode(
        name: p.basename(relativePath),
        type: SourceNodeType.image,
        content: SourceImageConfig(path: relativePath, slicing: config),
        parentId: null, // Add to root of Source Tree
      );

      // d. Create Sprite Nodes if requested
      if (result.asSprites) {
        final spriteName = p.basenameWithoutExtension(file.name);
        
        // Create the sprite node
        // Note: If creating an animation later, we still create the nodes first, 
        // then move them into the animation container.
        final spriteNode = _notifier.createNode(
          type: PackerItemType.sprite,
          name: spriteName,
          parentId: outputParentId,
        );
        
        // Link Sprite to the Source Node ID
        _notifier.updateSpriteDefinition(spriteNode.id, SpriteDefinition(
          sourceImageId: sourceNode.id,
          gridRect: const GridRect(x: 0, y: 0, width: 1, height: 1),
        ));
        
        createdSpriteNodeIds.add(spriteNode.id);
        createdNames.add(spriteName);
      }
    }

    // 4. Finalize Animation Creation if needed
    if (mode == 'anim' && baseName != null && createdSpriteNodeIds.isNotEmpty) {
      final settings = ref.read(effectiveSettingsProvider
        .select((s) => s.pluginSettings[TexturePackerSettings] as TexturePackerSettings?));

      // This method creates the Anim node and moves the sprite nodes into it
      _notifier.createAnimationFromExistingSprites(
        name: baseName,
        frameNodeIds: createdSpriteNodeIds,
        parentId: outputParentId,
        speed: settings?.defaultAnimationSpeed ?? 10.0,
      );
      
      MachineToast.info('Created animation "$baseName" with ${createdSpriteNodeIds.length} frames.');
    } else if (createdNames.isNotEmpty) {
      MachineToast.info('Imported ${createdNames.length} sprites.');
    } else {
      MachineToast.info('Imported ${result.files.length} source images.');
    }
    
    // Refresh asset loading
    _updateAndLoadAssetUris();
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
    } else if (_mode == TexturePackerMode.preview) {
      appBarOverride = PreviewAppBar(
        tabId: widget.tab.id,
        onExit: () => setMode(TexturePackerMode.panZoom),
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
  
  PackerItemNode? _findNodeById(PackerItemNode node, String id) {
    if (node.id == id) {
      return node;
    }
    for (final child in node.children) {
      final found = _findNodeById(child, id);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  GridRect? _pixelToGridRect(Offset positionInImage, SlicingConfig slicing) {
    if (positionInImage.dx < slicing.margin || positionInImage.dy < slicing.margin) {
      return null;
    }
    final effectiveX = positionInImage.dx - slicing.margin;
    final effectiveY = positionInImage.dy - slicing.margin;
    final cellWidthWithPadding = slicing.tileWidth + slicing.padding;
    final cellHeightWithPadding = slicing.tileHeight + slicing.padding;

    if (cellWidthWithPadding <= 0 || cellHeightWithPadding <= 0) {
      return null;
    }

    final gridX = (effectiveX / cellWidthWithPadding).floor();
    final gridY = (effectiveY / cellHeightWithPadding).floor();

    if (effectiveX % cellWidthWithPadding >= slicing.tileWidth) {
      return null;
    }
    if (effectiveY % cellHeightWithPadding >= slicing.tileHeight) {
      return null;
    }
    return GridRect(x: gridX, y: gridY, width: 1, height: 1);
  }
    
  
  @override
  void undo() {}
  @override
  void redo() {}
  
  @override
  Future<EditorContent> getContent() async {
    final currentState = _notifier.project;
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
    return Stack(
      children: [
        _buildMainContent(),
        Positioned(
          top: 8,
          right: 8,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              // --- COMMAND SYSTEM REFACTOR ---
              // Reference the new, specific CommandPosition from TexturePackerPlugin.
              child: CommandToolbar(position: TexturePackerPlugin.textureFloatingToolbar),
              // --- END REFACTOR ---
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          top: 0,
          bottom: 0,
          left: _isSourceImagesPanelVisible ? 0 : -251,
          width: 250,
          child: SourceImagesPanel(
            notifier: _notifier, 
            onAddImage: _promptAndAddSourceImages,
            onClose: toggleSourceImagesPanel,
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          top: 0,
          bottom: 0,
          right: _isHierarchyPanelVisible ? 0 : -301,
          width: 300,
          child: HierarchyPanel(
            notifier: _notifier,
            onClose: toggleHierarchyPanel,
          ),
        ),
      ],
    );
  }
  
  Widget _buildMainContent() {
    if (_mode == TexturePackerMode.preview) {
      return PreviewView(tabId: widget.tab.id, notifier: _notifier);
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
            onPressed: _promptAndAddSourceImages,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add First Source Image'),
          ),
        ],
      ),
    );
  }

  Widget _buildSlicingView() {
    final activeIndex = ref.watch(activeSourceImageIndexProvider);
    final project = _notifier.project;

    if (project.sourceImages.isEmpty) {
        return _buildEmptyState();
    }

    if (activeIndex >= project.sourceImages.length) {
      return const Center(child: Text('Select a source image.'));
    }

    final sourceConfig = project.sourceImages[activeIndex];
    
    return SlicingView(
      tabId: widget.tab.id,
      notifier: _notifier,
      transformationController: _transformationController,
      dragSelection: _selectionRect,
      isPanZoomMode: _mode == TexturePackerMode.panZoom,
      onGestureStart: (pos) => onSlicingGestureStart(pos, sourceConfig.slicing),
      onGestureUpdate: (pos) => onSlicingGestureUpdate(pos, sourceConfig.slicing),
      onGestureEnd: onSlicingGestureEnd,
    );
  }
}