import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_settings.dart';
import 'package:machine/settings/settings_notifier.dart';
import '../texture_packer_preview_state.dart';

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

  // Collects all sprites within a folder (recursive)
  List<SpriteDefinition> _collectSpritesInFolder(PackerItemNode folder, Map<String, PackerItemDefinition> defs) {
    List<SpriteDefinition> sprites = [];
    for (final child in folder.children) {
      if (child.type == PackerItemType.folder) {
        sprites.addAll(_collectSpritesInFolder(child, defs));
      } else if (child.type == PackerItemType.sprite) {
        final def = defs[child.id];
        if (def is SpriteDefinition) {
          sprites.add(def);
        }
      }
    }
    return sprites;
  }

  void _updateAnimationState(AnimationDefinition animDef, PreviewState state) {
    if (animDef.frameIds.isEmpty || animDef.speed <= 0) {
      _animationController.stop();
      _currentAnimationDef = null;
      _frameAnimation = null;
      return;
    }

    // Update controller parameters
    final effectiveSpeed = animDef.speed * state.speedMultiplier;
    final durationMs = (animDef.frameIds.length / effectiveSpeed * 1000).round();
    final newDuration = Duration(milliseconds: durationMs > 0 ? durationMs : 1000);

    bool configChanged = animDef != _currentAnimationDef || 
                         _animationController.duration != newDuration;

    if (configChanged) {
      _currentAnimationDef = animDef;
      _animationController.duration = newDuration;
      _frameAnimation = StepTween(begin: 0, end: animDef.frameIds.length).animate(_animationController);
    }

    if (state.isPlaying) {
      if (!_animationController.isAnimating) {
        state.isLooping ? _animationController.repeat() : _animationController.forward();
      }
    } else {
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final project = widget.notifier.project;
    final assetMap = ref.watch(assetMapProvider(widget.tabId));
    final previewState = ref.watch(previewStateProvider(widget.tabId));
    
    final settings = ref.watch(effectiveSettingsProvider
        .select((s) => s.pluginSettings[TexturePackerSettings] as TexturePackerSettings?)) 
        ?? TexturePackerSettings();

    return assetMap.when(
      data: (assets) {
        Widget content;
        
        if (selectedNodeId == null) {
          content = _buildPlaceholder('No Item Selected', 'Select an item to preview.');
        } else {
          final node = _findNodeById(project.tree, selectedNodeId);
          if (node == null) {
            content = _buildPlaceholder('Error', 'Item not found.');
          } else if (node.type == PackerItemType.folder || node.id == 'root') {
            // Folder / Root -> Atlas View
            final sprites = _collectSpritesInFolder(node, project.definitions);
            content = _buildAtlasPreview(sprites, project, assets);
          } else {
            final definition = project.definitions[node.id];
            
            if (definition is SpriteDefinition) {
              _animationController.stop();
              content = _buildSpritePreview(project, definition, assets);
            } else if (definition is AnimationDefinition) {
              _updateAnimationState(definition, previewState);
              content = _buildAnimationPreview(project, definition, assets);
            } else {
              content = _buildPlaceholder('No Data', 'Item definition missing.');
            }
          }
        }

        return Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            children: [
              if (previewState.showGrid)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BackgroundPainter(settings: settings),
                  ),
                ),
              InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.1,
                maxScale: 16.0,
                child: Center(child: content),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildSpritePreview(
    TexturePackerProject project,
    SpriteDefinition spriteDef,
    Map<String, AssetData> assets,
  ) {
    if (spriteDef.sourceImageIndex >= project.sourceImages.length) return const Icon(Icons.broken_image);
    
    final sourceConfig = project.sourceImages[spriteDef.sourceImageIndex];
    final asset = assets[sourceConfig.path];

    if (asset is! ImageAssetData) return const Icon(Icons.broken_image);

    final srcRect = _calculateSourceRect(sourceConfig, spriteDef.gridRect);

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
      return _buildPlaceholder('Empty Animation', 'No frames defined.');
    }

    // Handle loop end behavior for UI purposes (prevent out of bounds)
    var frameIndex = _frameAnimation!.value;
    if (frameIndex >= animDef.frameIds.length) frameIndex = 0;

    final frameId = animDef.frameIds[frameIndex];
    final spriteDef = project.definitions[frameId] as SpriteDefinition?;

    if (spriteDef == null) return const Icon(Icons.error_outline);
    
    return _buildSpritePreview(project, spriteDef, assets);
  }

  Widget _buildAtlasPreview(
    List<SpriteDefinition> sprites,
    TexturePackerProject project,
    Map<String, AssetData> assets,
  ) {
    if (sprites.isEmpty) return _buildPlaceholder('Empty Folder', 'No sprites to display.');

    // Simple grid layout for visualization
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: sprites.map((def) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
          ),
          child: _buildSpritePreview(project, def, assets),
        );
      }).toList(),
    );
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        Text(message),
      ],
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final TexturePackerSettings settings;
  _BackgroundPainter({required this.settings});

  @override
  void paint(Canvas canvas, Size size) {
    final c1 = Color(settings.checkerBoardColor1);
    final c2 = Color(settings.checkerBoardColor2);
    final paint = Paint();
    const double checkerSize = 20.0;

    // Draw full screen checkerboard
    final cols = (size.width / checkerSize).ceil();
    final rows = (size.height / checkerSize).ceil();

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        paint.color = ((x + y) % 2 == 0) ? c1 : c2;
        canvas.drawRect(
          Rect.fromLTWH(x * checkerSize, y * checkerSize, checkerSize, checkerSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) => oldDelegate.settings != settings;
}

// Reused simple painter for single sprite rendering
class _SpritePainter extends CustomPainter {
  final ui.Image image;
  final Rect srcRect;

  _SpritePainter({required this.image, required this.srcRect});

  @override
  void paint(Canvas canvas, Size size) {
    final destinationRect = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImageRect(image, srcRect, destinationRect, paint);
  }

  @override
  bool shouldRepaint(_SpritePainter oldDelegate) => false;
}