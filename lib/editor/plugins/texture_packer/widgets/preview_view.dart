// lib/editor/plugins/texture_packer/widgets/preview_view.dart

import 'dart:ui' as ui;
import 'dart:math' as math;
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
  late final TransformationController _transformationController;
  
  Animation<int>? _frameAnimation;
  String? _currentAnimationNodeId; 
  bool _needsFit = true;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(vsync: this);
    
    _animationController.addListener(() => setState(() {}));
    
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        final state = ref.read(previewStateProvider(widget.tabId));
        if (!state.isLooping) {
          ref.read(previewStateProvider(widget.tabId).notifier).state = 
              state.copyWith(isPlaying: false);
          _animationController.reset();
        }
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  // --- Helpers ---

  PackerItemNode? _findNodeById(PackerItemNode node, String id) {
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = _findNodeById(child, id);
      if (found != null) return found;
    }
    return null;
  }

  SourceImageConfig? _findSourceConfig(String sourceId) {
    return widget.notifier.findSourceImageConfig(sourceId);
  }

  List<SpriteDefinition> _collectSpritesInFolder(PackerItemNode folder) {
    List<SpriteDefinition> sprites = [];
    for (final child in folder.children) {
      if (child.type == PackerItemType.folder) {
        sprites.addAll(_collectSpritesInFolder(child));
      } else if (child.type == PackerItemType.sprite) {
        final def = widget.notifier.project.definitions[child.id];
        if (def is SpriteDefinition) {
          sprites.add(def);
        }
      }
    }
    return sprites;
  }

  // --- Animation Logic ---

  void _updateAnimationState(PackerItemNode node, AnimationDefinition animDef, PreviewState state) {
    final frameCount = node.children.length;

    if (frameCount == 0 || animDef.speed <= 0) {
      _animationController.stop();
      _currentAnimationNodeId = null;
      _frameAnimation = null;
      return;
    }

    final effectiveSpeed = animDef.speed * state.speedMultiplier;
    final durationMs = (frameCount / effectiveSpeed * 1000).round();
    final newDuration = Duration(milliseconds: durationMs > 0 ? durationMs : 1000);

    bool configChanged = node.id != _currentAnimationNodeId || 
                         _animationController.duration != newDuration;

    if (configChanged) {
      _currentAnimationNodeId = node.id;
      _animationController.duration = newDuration;
      _frameAnimation = StepTween(begin: 0, end: frameCount).animate(_animationController);
    }

    if (state.isPlaying) {
      if (!_animationController.isAnimating && 
          _animationController.status != AnimationStatus.completed) {
        state.isLooping ? _animationController.repeat() : _animationController.forward();
      } else if (state.isLooping && !_animationController.isAnimating) {
         _animationController.repeat();
      }
    } else {
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
    }
  }

  void _fitContent(Size contentSize, Size viewportSize) {
    if (contentSize.isEmpty || viewportSize.isEmpty) return;

    final double margin = 32.0;
    final double availableW = viewportSize.width - margin * 2;
    final double availableH = viewportSize.height - margin * 2;

    final double scaleX = availableW / contentSize.width;
    final double scaleY = availableH / contentSize.height;
    // Limit scale to avoid tiny images blowing up too much, or huge images disappearing
    final double scale = math.min(scaleX, scaleY).clamp(0.1, 10.0); 

    // Calculate offset to center the scaled content
    final double offsetX = (viewportSize.width - contentSize.width * scale) / 2;
    final double offsetY = (viewportSize.height - contentSize.height * scale) / 2;

    _transformationController.value = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(scale);

    _needsFit = false;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    
    // Listen for selection changes to reset "fit to screen" logic
    ref.listen(selectedNodeIdProvider, (prev, next) {
      if (prev != next) {
        setState(() {
          _needsFit = true;
          _animationController.stop();
          _animationController.reset();
        });
      }
    });

    final assetMap = ref.watch(assetMapProvider(widget.tabId));
    final previewState = ref.watch(previewStateProvider(widget.tabId));
    final settings = ref.watch(effectiveSettingsProvider
        .select((s) => s.pluginSettings[TexturePackerSettings] as TexturePackerSettings?)) 
        ?? TexturePackerSettings();

    return assetMap.when(
      data: (assets) {
        Widget content;
        Size contentSize = Size.zero;
        
        if (selectedNodeId == null) {
          content = _buildPlaceholder('No Item Selected', 'Select a sprite or animation to preview.');
        } else {
          final node = _findNodeById(widget.notifier.project.tree, selectedNodeId);
          
          if (node == null) {
            content = _buildPlaceholder('Item Not Found', 'The selected item may have been deleted.');
          } else if (node.type == PackerItemType.folder || node.id == 'root') {
            // Folder / Root Preview
            final sprites = _collectSpritesInFolder(node);
            content = _buildAtlasPreview(sprites, assets);
            // Don't auto-fit folders as they can be huge; use default size and let user pan
            contentSize = const Size(500, 500); 
          } else {
            // Sprite or Animation
            final definition = widget.notifier.project.definitions[node.id];
            
            if (definition is SpriteDefinition) {
              _animationController.stop();
              final size = _getSpriteSize(definition);
              contentSize = size ?? Size.zero;
              content = _buildSpritePreview(definition, assets, size);
            } else if (definition is AnimationDefinition) {
              _updateAnimationState(node, definition, previewState);
              
              if (node.children.isNotEmpty) {
                 final firstFrameDef = widget.notifier.project.definitions[node.children.first.id];
                 if (firstFrameDef is SpriteDefinition) {
                   contentSize = _getSpriteSize(firstFrameDef) ?? Size.zero;
                 }
              }
              content = _buildAnimationPreview(node, assets, contentSize);
            } else {
              content = _buildPlaceholder('No Data', 'Item definition missing.');
            }
          }
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // Auto-fit logic: runs once per selection change when content size is known
            if (_needsFit && !contentSize.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _needsFit) {
                  _fitContent(contentSize, constraints.biggest);
                }
              });
            }

            return Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Stack(
                children: [
                  if (previewState.showGrid)
                    Positioned.fill(
                      child: CustomPaint(painter: _BackgroundPainter(settings: settings)),
                    ),
                  InteractiveViewer(
                    transformationController: _transformationController,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.01,
                    maxScale: 20.0,
                    // Use constrained: false so boundaries don't force centering before transform
                    constrained: false, 
                    child: contentSize.isEmpty 
                      ? SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: Center(child: content),
                        )
                      : Align(
                          // CORRECTED: Align top-left so the matrix translation 
                          // (which assumes 0,0 origin) centers it correctly.
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: contentSize.width, 
                            height: contentSize.height, 
                            child: content
                          ),
                        ),
                  ),
                ],
              ),
            );
          }
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading assets: $err')),
    );
  }

  Size? _getSpriteSize(SpriteDefinition def) {
    final sourceConfig = _findSourceConfig(def.sourceImageId);
    if (sourceConfig == null) return null;
    final rect = _calculateSourceRect(sourceConfig, def.gridRect);
    return Size(rect.width, rect.height);
  }

  Widget _buildSpritePreview(
    SpriteDefinition spriteDef,
    Map<String, AssetData> assets,
    Size? precalcSize,
  ) {
    final sourceConfig = _findSourceConfig(spriteDef.sourceImageId);
    if (sourceConfig == null) return const Icon(Icons.broken_image, size: 48);

    final asset = assets[sourceConfig.path];
    if (asset is! ImageAssetData) return const Icon(Icons.broken_image, size: 48);

    final srcRect = _calculateSourceRect(sourceConfig, spriteDef.gridRect);
    final size = precalcSize ?? Size(srcRect.width, srcRect.height);

    return CustomPaint(
      size: size,
      painter: _SpritePainter(image: asset.image, srcRect: srcRect),
    );
  }

  Widget _buildAnimationPreview(
    PackerItemNode animNode,
    Map<String, AssetData> assets,
    Size frameSize,
  ) {
    if (_frameAnimation == null || animNode.children.isEmpty) {
      return _buildPlaceholder('Empty Animation', 'Add sprites to this animation.');
    }

    var frameIndex = _frameAnimation!.value;
    if (frameIndex >= animNode.children.length) frameIndex = 0;

    final frameNode = animNode.children[frameIndex];
    final spriteDef = widget.notifier.project.definitions[frameNode.id] as SpriteDefinition?;

    if (spriteDef == null) return const Icon(Icons.error_outline);
    
    return _buildSpritePreview(spriteDef, assets, frameSize);
  }

  Widget _buildAtlasPreview(
    List<SpriteDefinition> sprites,
    Map<String, AssetData> assets,
  ) {
    if (sprites.isEmpty) return _buildPlaceholder('Empty Folder', 'No sprites to display.');

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: sprites.map((def) {
        final size = _getSpriteSize(def);
        return Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.white24)),
          child: _buildSpritePreview(def, assets, size),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// Painters (Identical to original)
class _BackgroundPainter extends CustomPainter {
  final TexturePackerSettings settings;
  _BackgroundPainter({required this.settings});
  @override
  void paint(Canvas canvas, Size size) {
    final c1 = Color(settings.checkerBoardColor1);
    final c2 = Color(settings.checkerBoardColor2);
    final paint = Paint();
    const double checkerSize = 20.0;
    final cols = (size.width / checkerSize).ceil();
    final rows = (size.height / checkerSize).ceil();
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        paint.color = ((x + y) % 2 == 0) ? c1 : c2;
        canvas.drawRect(Rect.fromLTWH(x * checkerSize, y * checkerSize, checkerSize, checkerSize), paint);
      }
    }
  }
  @override
  bool shouldRepaint(_BackgroundPainter old) => old.settings != settings;
}

class _SpritePainter extends CustomPainter {
  final ui.Image image;
  final Rect srcRect;
  _SpritePainter({required this.image, required this.srcRect});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(image, srcRect, Offset.zero & size, Paint()..filterQuality = FilterQuality.none);
  }
  @override
  bool shouldRepaint(_SpritePainter old) => old.image != image || old.srcRect != srcRect;
}