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
  const PreviewView({super.key, required this.tabId});

  @override
  ConsumerState<PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends ConsumerState<PreviewView> with TickerProviderStateMixin {
  late final AnimationController _animationController;
  Animation<int>? _frameAnimation;

  // Store the last seen animation definition to check for updates
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

  /// Finds a node by its ID in the project tree recursively.
  PackerItemNode? _findNodeById(PackerItemNode node, String id) {
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = _findNodeById(child, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Configures or re-configures the AnimationController for a given animation.
  void _setupAnimationController(AnimationDefinition animDef) {
    if (animDef.frameIds.isEmpty) {
      _animationController.stop();
      return;
    }

    // Check if the animation has changed since last build
    if (animDef.frameIds != _currentAnimationDef?.frameIds || animDef.speed != _currentAnimationDef?.speed) {
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
    final project = ref.watch(texturePackerNotifierProvider(widget.tabId));
    final assetMap = ref.watch(assetMapProvider(widget.tabId));

    return assetMap.when(
      data: (assets) {
        if (selectedNodeId == null) {
          return _buildPlaceholder('No Item Selected', 'Select a sprite or animation from the hierarchy panel to preview it here.');
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
          return _buildPlaceholder('No Data', 'This item has not been defined yet.');
        }

        Widget previewContent;

        if (definition is SpriteDefinition) {
          _animationController.stop(); // Stop any running animation
          previewContent = _buildSpritePreview(project, definition, assets);
        } else if (definition is AnimationDefinition) {
          _setupAnimationController(definition);
          previewContent = _buildAnimationPreview(project, definition, assets);
        } else {
          previewContent = const SizedBox.shrink();
        }

        return InteractiveViewer(
          boundaryMargin: const EdgeInsets.all(50),
          minScale: 0.1,
          maxScale: 16.0,
          child: Center(child: previewContent),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => _buildPlaceholder('Asset Error', err.toString()),
    );
  }

  Widget _buildSpritePreview(
    TexturePackerProject project,
    SpriteDefinition spriteDef,
    Map<String, AssetData> assets,
  ) {
    final sourceImageConfig = project.sourceImages[spriteDef.sourceImageIndex];
    final asset = assets[sourceImageConfig.path];

    if (asset is! ImageAssetData) {
      return _buildPlaceholder('Image Error', 'Could not load source image: ${sourceImageConfig.path}');
    }

    final srcRect = _calculateSourceRect(sourceImageConfig, spriteDef.gridRect);

    return CustomPaint(
      size: Size(srcRect.width, srcRect.height),
      painter: _SpritePainter(image: asset.image, srcRect: srcRect),
    );
  }

  Widget _buildAnimationPreview(
    TexturePackerProject project,
    AnimationDefinition animDef,
    Map<String, AssetData> assets,
  ) {
    if (_frameAnimation == null || animDef.frameIds.isEmpty) {
      return _buildPlaceholder('Empty Animation', 'Add frames to this animation.');
    }

    final frameId = animDef.frameIds[_frameAnimation!.value];
    final spriteDef = project.definitions[frameId] as SpriteDefinition?;

    if (spriteDef == null) {
      return _buildPlaceholder('Frame Error', 'Frame "$frameId" is not defined.');
    }
    
    // Reuse the single sprite preview logic
    return _buildSpritePreview(project, spriteDef, assets);
  }

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
    return Center(
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
    // Draw a checkerboard background
    final checkerPaint1 = Paint()..color = const Color(0xFFCCCCCC);
    final checkerPaint2 = Paint()..color = const Color(0xFF888888);
    const double checkerSize = 16.0;
    for (double i = 0; i < size.width; i += checkerSize) {
      for (double j = 0; j < size.height; j += checkerSize) {
        final paint = ((i + j) / checkerSize) % 2 == 0 ? checkerPaint1 : checkerPaint2;
        canvas.drawRect(Rect.fromLTWH(i, j, checkerSize, checkerSize), paint);
      }
    }
    
    // Fit the sprite within the canvas while preserving aspect ratio
    final fittedSizes = applyBoxFit(BoxFit.contain, srcRect.size, size);
    final sourceRect = fittedSizes.source; // Not used for drawImageRect, but good practice
    final destinationRect = fittedSizes.destination;

    final paint = Paint()..filterQuality = FilterQuality.none;

    // Draw the specific portion of the spritesheet image
    canvas.drawImageRect(image, srcRect, destinationRect, paint);
  }

  @override
  bool shouldRepaint(_SpritePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.srcRect != srcRect;
  }
}