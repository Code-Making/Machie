// lib/editor/plugins/texture_packer/texture_packer_editor_widget.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/command/command_widgets.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/models/editor_command_context.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/project/project_settings_notifier.dart';
import 'package:machine/utils/toast.dart';

import 'texture_packer_command_context.dart';
import 'texture_packer_editor_models.dart';
import 'texture_packer_models.dart';
import 'texture_packer_notifier.dart';
import 'texture_packer_plugin.dart';
import 'texture_packer_settings.dart';

import 'widgets/hierarchy_panel.dart';
import 'widgets/preview_view.dart';
import 'widgets/preview_app_bar.dart';
import 'widgets/slicing_app_bar.dart';
import 'widgets/slicing_view.dart';
import 'widgets/slicing_properties_dialog.dart';
import 'widgets/source_images_panel.dart';
import 'widgets/texture_packer_file_dialog.dart';

// Providers for UI state
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
  
  // Cache for asset loading
  Set<String> _requiredAssetUris = const {};

  // View State
  TexturePackerMode _mode = TexturePackerMode.panZoom;
  bool _isSourceImagesPanelVisible = false;
  bool _isHierarchyPanelVisible = false;
  
  // Transformation Controller for the Slicing View
  late final TransformationController _transformationController;
  
  // Temporary Slicing State
  Offset? _dragStart;
  GridRect? _selectionRect;

  @override
  void init() {
    _transformationController = TransformationController();
    _notifier = TexturePackerNotifier(widget.tab.initialProjectState);
    _notifier.addListener(_onNotifierUpdate);
  }
  
  /// Called whenever the data model changes (add/move/delete)
  void _onNotifierUpdate() {
    if (!mounted) return;

    // 1. Sanitize Selection State
    // If the currently selected node or source image was deleted, clear the selection
    // to prevent the UI from trying to render a null object.
    final currentSourceId = ref.read(activeSourceImageIdProvider);
    if (currentSourceId != null) {
      if (_notifier.findSourceImageConfig(currentSourceId) == null) {
        ref.read(activeSourceImageIdProvider.notifier).state = null;
      }
    }

    // 2. Mark Dirty
    ref.read(editorServiceProvider).markCurrentTabDirty();
    
    // 3. Sync Commands
    syncCommandContext();
    
    // 4. Refresh Asset Dependencies
    _updateAndLoadAssetUris();
    
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
    _updateAndLoadAssetUris();
    syncCommandContext();
  }

  /// Traverses the SourceImage tree to find all file paths and tells the
  /// asset system to load them.
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

    // Only trigger a reload if the set of URIs actually changed
    if (!const SetEquality().equals(uris, _requiredAssetUris)) {
      _requiredAssetUris = uris;
      ref.read(assetMapProvider(widget.tab.id).notifier).updateUris(uris);
    }
  }

  // ---------------------------------------------------------------------------
  // UI Commands
  // ---------------------------------------------------------------------------

  void setMode(TexturePackerMode newMode) {
    if (_mode == newMode) {
      // Toggle back to default
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

  // ---------------------------------------------------------------------------
  // Slicing Logic
  // ---------------------------------------------------------------------------

  // ... (Slicing logic remains mostly same, but ensures null safety) ...
  Point<int>? _pixelToGridPoint(Offset positionInImage, SlicingConfig slicing) {
    if (positionInImage.dx < slicing.margin || positionInImage.dy < slicing.margin) return null;
    
    final effectiveX = positionInImage.dx - slicing.margin;
    final effectiveY = positionInImage.dy - slicing.margin;
    final cellW = slicing.tileWidth + slicing.padding;
    final cellH = slicing.tileHeight + slicing.padding;

    if (cellW <= 0 || cellH <= 0) return null;

    final gridX = (effectiveX / cellW).floor();
    final gridY = (effectiveY / cellH).floor();

    if (effectiveX % cellW >= slicing.tileWidth || effectiveY % cellH >= slicing.tileHeight) return null;

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
  }

  Future<void> confirmSpriteSelection() async {
    if (_selectionRect == null) return;
    final rect = _selectionRect!;
    
    // Check if we actually have an active source image to attach this sprite to
    final activeImageId = ref.read(activeSourceImageIdProvider);
    if (activeImageId == null) {
      MachineToast.error("No source image selected.");
      return;
    }

    final bool isMulti = rect.width > 1 || rect.height > 1;

    if (!isMulti) {
      await _createSingleSprite(rect, activeImageId);
    } else {
      await _handleMultiSelection(rect, activeImageId);
    }
    cancelSpriteSelection();
  }

  Future<void> _createSingleSprite(GridRect rect, String activeImageId) async {
    final spriteName = await showTextInputDialog(context, title: 'Create New Sprite');
    if (spriteName != null && spriteName.trim().isNotEmpty) {
      // Determine parent from current selection, falling back to root
      String parentId = ref.read(selectedNodeIdProvider) ?? 'root';
      
      // Ensure we don't try to parent into a sprite (which can't have children)
      // This logic relies on the notifier's safety checks, but good to check here for UX
      
      final newNode = _notifier.createNode(
        type: PackerItemType.sprite,
        name: spriteName.trim(),
        parentId: parentId, 
      );

      _notifier.updateSpriteDefinition(newNode.id, SpriteDefinition(
        sourceImageId: activeImageId,
        gridRect: rect,
      ));
      
      ref.read(selectedNodeIdProvider.notifier).state = newNode.id;
    }
  }

  Future<void> _handleMultiSelection(GridRect rect, String activeImageId) async {
    // ... (Dialog logic same as Phase 1) ...
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
            child: const ListTile(leading: Icon(Icons.movie), title: Text(optionAnim)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, optionBatch),
            child: const ListTile(leading: Icon(Icons.copy_all), title: Text(optionBatch)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, optionSingle),
            child: const ListTile(leading: Icon(Icons.crop_free), title: Text(optionSingle)),
          ),
        ],
      ),
    );

    if (choice == null) return;

    if (choice == optionSingle) {
      await _createSingleSprite(rect, activeImageId);
      return;
    }

    final baseName = await showTextInputDialog(context, title: 'Base Name');
    if (baseName == null || baseName.trim().isEmpty) return;
    
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
      // 1. Create sprites
      final nodes = _notifier.createBatchSprites(
        names: names,
        definitions: definitions,
        parentId: parentId, 
      );
      
      final settings = ref.read(effectiveSettingsProvider
        .select((s) => s.pluginSettings[TexturePackerSettings] as TexturePackerSettings?));
      
      // 2. Create animation container and move sprites into it
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
  
  // ---------------------------------------------------------------------------
  // Import Logic
  // ---------------------------------------------------------------------------

  Future<void> _promptAndAddSourceImages() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null) return;

    final result = await showDialog<TexturePackerImportResult>(
      context: context,
      builder: (_) => TexturePackerFilePickerDialog(projectRootUri: project.rootUri),
    );

    if (result == null || result.files.isEmpty) return;

    final repo = ref.read(projectRepositoryProvider)!;
    final outputParentId = ref.read(selectedNodeIdProvider); 

    // Logic for "Import as Animation" vs "Batch"
    String mode = 'batch'; 
    String? baseName;
    
    if (result.asSprites && result.files.length > 1) {
      // ... (Show dialog to choose 'anim' or 'batch', same as Phase 1) ...
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Import Mode'),
          children: [
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'batch'),
                child: const Text('Batch Sprites'),
            ),
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'anim'),
                child: const Text('Animation'),
            ),
          ],
        ),
      );
      if (choice == null) return; 
      mode = choice;
      if (mode == 'anim') {
        baseName = await showTextInputDialog(context, title: 'Animation Name');
        if (baseName == null || baseName.trim().isEmpty) return;
      }
    }

    final List<String> createdSpriteNodeIds = [];

    for (final file in result.files) {
      final relativePath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: project.rootUri);

      // Load dimensions eagerly if importing as sprites
      SlicingConfig config = const SlicingConfig();
      if (result.asSprites) {
        try {
          final assetData = await ref.read(assetDataProvider(relativePath).future);
          if (assetData is ImageAssetData) {
            config = SlicingConfig(tileWidth: assetData.image.width, tileHeight: assetData.image.height);
          }
        } catch (_) {}
      }

      // 1. Add Source Node
      final sourceNode = _notifier.addSourceNode(
        name: p.basename(relativePath),
        type: SourceNodeType.image,
        content: SourceImageConfig(path: relativePath, slicing: config),
        parentId: null, // Add to root
      );

      // 2. Create Linked Sprite if requested
      if (result.asSprites) {
        final spriteName = p.basenameWithoutExtension(file.name);
        final spriteNode = _notifier.createNode(
          type: PackerItemType.sprite,
          name: spriteName,
          parentId: outputParentId,
        );
        _notifier.updateSpriteDefinition(spriteNode.id, SpriteDefinition(
          sourceImageId: sourceNode.id,
          gridRect: const GridRect(x: 0, y: 0, width: 1, height: 1),
        ));
        createdSpriteNodeIds.add(spriteNode.id);
      }
    }

    // 3. Convert to Animation if needed
    if (mode == 'anim' && baseName != null && createdSpriteNodeIds.isNotEmpty) {
       _notifier.createAnimationFromExistingSprites(
        name: baseName,
        frameNodeIds: createdSpriteNodeIds,
        parentId: outputParentId,
       );
    }
    
    // Explicitly refresh assets to ensure the new images appear
    _updateAndLoadAssetUris();
  }

  // ---------------------------------------------------------------------------
  // Framework Overrides
  // ---------------------------------------------------------------------------

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
  
  @override
  void undo() {} // Not implemented in this phase
  @override
  void redo() {} // Not implemented in this phase
  
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedNodeIdProvider, (previous, next) {
      if (next != null) {
        final def = _notifier.project.definitions[next];
        if (def is SpriteDefinition) {
          // If a sprite is selected, switch the active source image to match it.
          // This allows the user to immediately see where the sprite comes from.
          ref.read(activeSourceImageIdProvider.notifier).state = def.sourceImageId;
        }
      }
    });

    return Stack(
      children: [
        // 1. Main Content Area (Slicing or Preview)
        _buildMainContent(),
        
        // 2. Floating Toolbar
        Positioned(
          top: 8,
          right: 8,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: CommandToolbar(position: TexturePackerPlugin.textureFloatingToolbar),
            ),
          ),
        ),
        
        // 3. Left Panel (Source Images) - Uses New Flat List Widget
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
        
        // 4. Right Panel (Hierarchy) - Uses New Flat List Widget
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
    
    // Robust Empty State Check
    if (_notifier.getAllSourceImages().isEmpty) {
        return _buildEmptyState();
    }

    // Ensure we have a valid active image to slice
    final activeId = ref.watch(activeSourceImageIdProvider);
    if (activeId == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Select a source image from the panel to start slicing.'),
          ],
        ),
      );
    }

    final sourceConfig = _notifier.findSourceImageConfig(activeId);
    if (sourceConfig == null) {
      // Cleanup happens in listener, but if we hit this, just show fallback
      return const Center(child: Text('Source image not found.'));
    }
    
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
}