import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';

class PreviewView extends ConsumerStatefulWidget {
  final String tabId;
  final TexturePackerNotifier notifier;
  const PreviewView({super.key, required this.tabId, required this.notifier});

  @override
  ConsumerState<PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends ConsumerState<PreviewView> with TickerProviderStateMixin {
  late final AnimationController _animationController;
  Animation<int>? _frameAnimation;
  AnimationDefinition? _currentAnimationDef;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this);
    _animationController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  PackerItemNode? _findNodeById(PackerItemNode node, String id) {
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = _findNodeById(child, id);
      if (found != null) return found;
    }
    return null;
  }

  void _setupAnimationController(AnimationDefinition animDef) {
    if (animDef.frameIds.isEmpty || animDef.speed <= 0) {
      _animationController.stop();
      _currentAnimationDef = null;
      _frameAnimation = null;
      return;
    }

    if (animDef != _currentAnimationDef) {
      _currentAnimationDef = animDef;
      _animationController.duration = Duration(
        milliseconds: (animDef.frameIds.length / animDef.speed * 1000).round(),
      );
      _frameAnimation = StepTween(begin: 0, end: animDef.frameIds.length).animate(_animationController);
      
      if (mounted) {
        _animationController.repeat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final project = widget.notifier.project;
    final assetMap = ref.watch(assetMapProvider(widget.tabId));

    return assetMap.when(
      data: (assets) {
        if (selectedNodeId == null) {
          return _buildPlaceholder('No Item Selected', 'Select a sprite or animation to preview.');
        }

        final node = _findNodeById(project.tree, selectedNodeId);
        if (node == null) {
          return _buildPlaceholder('Error', 'Selected item not found in tree.');
        }

        final definition = project.definitions[node.id];

        if (node.type == PackerItemType.folder) {
          return _buildPlaceholder('Folder Selected', 'Select a sprite or animation to preview.');
        }

        if (definition == null) {
          _animationController.stop();
          return _buildPlaceholder('No Data', 'This item has not been defined yet.\nSelect a region in the Slicing View to define it.');
        }

        Widget previewContent;

        // --- PREVIEW LOGIC REFACTOR ---
        // Handle both SpriteDefinition and AnimationDefinition.
        if (definition is SpriteDefinition) {
          // If a single sprite is selected, stop any running animation.
          _animationController.stop();
          _currentAnimationDef = null;
          previewContent = _buildSpritePreview(project, definition, assets);
        } else if (definition is AnimationDefinition) {
          _setupAnimationController(definition);
          previewContent = _buildAnimationPreview(project, definition, assets);
        } else {
          previewContent = const SizedBox.shrink();
        }

        // --- LAYOUT FIX ---
        // The InteractiveViewer now fills the available space, and its child
        // is wrapped in a Center widget to ensure it's properly aligned.
        return InteractiveViewer(
          boundaryMargin: const EdgeInsets.all(50),
          minScale: 0.1,
          maxScale: 16.0,
          child: Center(child: previewContent),
        );
        // --- END LAYOUT FIX ---
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => _buildPlaceholder('Asset Error', err.toString()),
    );
  }

  /// Builds the widget to preview a single sprite.
  Widget _buildSpritePreview(
    TexturePackerProject project,
    SpriteDefinition spriteDef,
    Map<String, AssetData> assets,
  ) {
    if (spriteDef.sourceImageIndex >= project.sourceImages.length) {
       return _buildPlaceholder('Data Error', 'Invalid source image index.');
    }
    
    final sourceImageConfig = project.sourceImages[spriteDef.sourceImageIndex];
    final asset = assets[sourceImageConfig.path];

    if (asset is! ImageAssetData) {
      return _buildPlaceholder('Image Error', 'Could not load source image:\n${sourceImageConfig.path}');
    }

    final srcRect = _calculateSourceRect(sourceImageConfig, spriteDef.gridRect);

    // The CustomPaint widget is explicitly sized to the sprite's dimensions.
    return CustomPaint(
      size: Size(srcRect.width, srcRect.height),
      painter: _SpritePainter(image: asset.image, srcRect: srcRect),
    );
  }

  /// Builds the widget to preview a running animation.
  Widget _buildAnimationPreview(
    TexturePackerProject project,
    AnimationDefinition animDef,
    Map<String, AssetData> assets,
  ) {
    if (_frameAnimation == null || animDef.frameIds.isEmpty) {
      return _buildPlaceholder('Empty Animation', 'Right-click this animation in the hierarchy to add frames.');
    }

    final frameId = animDef.frameIds[_frameAnimation!.value];
    final spriteDef = project.definitions[frameId] as SpriteDefinition?;

    if (spriteDef == null) {
      return _buildPlaceholder('Frame Error', 'Animation frame with ID "$frameId" is not defined or is not a sprite.');
    }
    
    // Re-use the single sprite preview logic for the current frame.
    return _buildSpritePreview(project, spriteDef, assets);
  }

  /// Helper to convert grid coordinates into pixel coordinates for clipping.
  Rect _calculateSourceRect(SourceImageConfig source, GridRect gridRect) {
    final slicing = source.slicing;
    final left = slicing.margin + gridRect.x * (slicing.tileWidth + slicing.padding);
    final top = slicing.margin + gridRect.y * (slicing.tileHeight + slicing.padding);
    final width = gridRect.width * slicing.tileWidth + (gridRect.width - 1) * slicing.padding;
    final height = gridRect.height * slicing.tileHeight + (gridRect.height - 1) * slicing.padding;
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }
  
  Widget _buildPlaceholder(String title, String message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(message, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// A painter that draws a single sprite from a larger spritesheet.
class _SpritePainter extends CustomPainter {
  final ui.Image image;
  final Rect srcRect;

  _SpritePainter({required this.image, required this.srcRect});

  @override
  void paint(Canvas canvas, Size size) {
    _drawCheckerboard(canvas, size);
    
    final destinationRect = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.none;

    canvas.drawImageRect(image, srcRect, destinationRect, paint);
  }

  void _drawCheckerboard(Canvas canvas, Size size) {
    final checkerPaint1 = Paint()..color = const Color(0xFFCCCCCC);
    final checkerPaint2 = Paint()..color = const Color(0xFF888888);
    const double checkerSize = 16.0;
    for (double i = 0; i < size.width; i += checkerSize) {
      for (double j = 0; j < size.height; j += checkerSize) {
        final paint = ((i + j) / checkerSize).floor() % 2 == 0 ? checkerPaint1 : checkerPaint2;
        canvas.drawRect(Rect.fromLTWH(i, j, checkerSize, checkerSize), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SpritePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.srcRect != srcRect;
  }
}