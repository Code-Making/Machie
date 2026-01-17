// FILE: lib/editor/plugins/texture_packer/texture_packer_editor_widget.dart

import 'dart:async';
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
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
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

  TexturePackerMode _mode = TexturePackerMode.panZoom;
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
    if (!mounted) return;

    final currentSourceId = ref.read(activeSourceImageIdProvider);
    if (currentSourceId != null) {
      if (_notifier.findSourceImageConfig(currentSourceId) == null) {
        ref.read(activeSourceImageIdProvider.notifier).state = null;
      }
    }

    ref.read(editorServiceProvider).markCurrentTabDirty();
    
    syncCommandContext();
    
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
  void _updateAndLoadAssetUris() {
    if (!mounted) return;
    
    final project = ref.read(appNotifierProvider).value?.currentProject;
    final repo = ref.read(projectRepositoryProvider);
    final tpackerFileMetadata = ref.read(tabMetadataProvider)[widget.tab.id];

    if (project == null || repo == null || tpackerFileMetadata == null) return;
    
    final tpackerPath = repo.fileHandler.getPathForDisplay(
      tpackerFileMetadata.file.uri, 
      relativeTo: project.rootUri
    );
    final tpackerDir = p.dirname(tpackerPath);

    final uris = <String>{};
    void collectPaths(SourceImageNode node) {
      if (node.type == SourceNodeType.image && node.content != null) {
        if (node.content!.path.isNotEmpty) {
          final resolvedPath = repo.resolveRelativePath(tpackerDir, node.content!.path);
          uris.add(resolvedPath);
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
      String parentId = ref.read(selectedNodeIdProvider) ?? 'root';
      
      
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
      final nodes = _notifier.createBatchSprites(
        names: names,
        definitions: definitions,
        parentId: parentId, 
      );
      
      final settings = ref.read(effectiveSettingsProvider
        .select((s) => s.pluginSettings[TexturePackerSettings] as TexturePackerSettings?));
      
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

    final result = await showDialog<TexturePackerImportResult>(
      context: context,
      builder: (_) => TexturePackerFilePickerDialog(projectRootUri: project.rootUri),
    );

    if (result == null || result.files.isEmpty) return;

    final repo = ref.read(projectRepositoryProvider)!;
    final outputParentId = ref.read(selectedNodeIdProvider); 

    final tpackerFileMetadata = ref.read(tabMetadataProvider)[widget.tab.id]!;
    final tpackerProjectRelativePath = repo.fileHandler.getPathForDisplay(
      tpackerFileMetadata.file.uri, 
      relativeTo: project.rootUri
    );
    final tpackerDirectory = p.dirname(tpackerProjectRelativePath);

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
      final imageProjectRelativePath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: project.rootUri);
      
      final pathRelativeToTpacker = p.relative(imageProjectRelativePath, from: tpackerDirectory).replaceAll(r'\', '/');

      SlicingConfig config = const SlicingConfig();
      if (result.asSprites) {
        try {
          final assetData = await ref.read(assetDataProvider(imageProjectRelativePath).future);
          if (assetData is ImageAssetData) {
            config = SlicingConfig(tileWidth: assetData.image.width, tileHeight: assetData.image.height);
          }
        } catch (_) {}
      }

      final sourceNode = _notifier.addSourceNode(
        name: p.basename(imageProjectRelativePath),
        type: SourceNodeType.image,
        content: SourceImageConfig(path: pathRelativeToTpacker, slicing: config),
        parentId: null,
      );

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

    if (mode == 'anim' && baseName != null && createdSpriteNodeIds.isNotEmpty) {
       _notifier.createAnimationFromExistingSprites(
        name: baseName,
        frameNodeIds: createdSpriteNodeIds,
        parentId: outputParentId,
       );
    }
    
    _updateAndLoadAssetUris();
  }


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
    ref.listen(selectedNodeIdProvider, (previous, next) {
      if (next != null) {
        final def = _notifier.project.definitions[next];
        if (def is SpriteDefinition) {
          ref.read(activeSourceImageIdProvider.notifier).state = def.sourceImageId;
        }
      }
    });

    return Stack(
      children: [
        _buildMainContent(),
        
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
    
    if (_notifier.getAllSourceImages().isEmpty) {
        return _buildEmptyState();
    }

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