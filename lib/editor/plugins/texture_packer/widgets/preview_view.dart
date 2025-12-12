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
  PackerItemNode? _currentAnimationNode; // Changed from Definition to Node to track children
  String? _lastSelectedNodeId;
  bool _needsFit = true;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(vsync: this);
    
    _animationController.addListener(() {
      setState(() {});
    });
    
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

  PackerItemNode? _findNodeById(PackerItemNode node, String id) {
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = _findNodeById(child, id);
      if (found != null) return found;
    }
    return null;
  }

  // Recursive helper to find source config in the new SourceImageNode tree
  SourceImageConfig? _findSourceConfig(SourceImageNode node, String id) {
    if (node.type == SourceNodeType.image && node.id == id) {
      return node.content;
    }
    for (final child in node.children) {
      final found = _findSourceConfig(child, id);
      if (found != null) return found;
    }
    return null;
  }

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

  void _updateAnimationState(PackerItemNode node, AnimationDefinition animDef, PreviewState state) {
    // Frames are the children of the animation node
    final frameCount = node.children.length;

    if (frameCount == 0 || animDef.speed <= 0) {
      _animationController.stop();
      _currentAnimationNode = null;
      _frameAnimation = null;
      return;
    }

    final effectiveSpeed = animDef.speed * state.speedMultiplier;
    final durationMs = (frameCount / effectiveSpeed * 1000).round();
    final newDuration = Duration(milliseconds: durationMs > 0 ? durationMs : 1000);

    bool configChanged = node != _currentAnimationNode || 
                         _animationController.duration != newDuration;

    if (configChanged) {
      _currentAnimationNode = node;
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
    final double scale = math.min(scaleX, scaleY).clamp(0.1, 10.0); 

    final double offsetX = (viewportSize.width - contentSize.width * scale) / 2;
    final double offsetY = (viewportSize.height - contentSize.height * scale) / 2;

    final Matrix4 matrix = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(scale);

    _transformationController.value = matrix;
    _needsFit = false;
  }

  @override
  Widget build(BuildContext context) {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final project = widget.notifier.project;
    final assetMap = ref.watch(assetMapProvider(widget.tabId));
    final previewState = ref.watch(previewStateProvider(widget.tabId));
    
    if (selectedNodeId != _lastSelectedNodeId) {
      _lastSelectedNodeId = selectedNodeId;
      _needsFit = true;
      _animationController.stop();
      _animationController.reset();
    }
    
    final settings = ref.watch(effectiveSettingsProvider
        .select((s) => s.pluginSettings[TexturePackerSettings] as TexturePackerSettings?)) 
        ?? TexturePackerSettings();

    return assetMap.when(
      data: (assets) {
        Widget content;
        Size contentSize = Size.zero;
        
        if (selectedNodeId == null) {
          content = _buildPlaceholder('No Item Selected', 'Select an item to preview.');
        } else {
          final node = _findNodeById(project.tree, selectedNodeId);
          if (node == null) {
            content = _buildPlaceholder('Error', 'Item not found.');
          } else if (node.type == PackerItemType.folder || node.id == 'root') {
            final sprites = _collectSpritesInFolder(node, project.definitions);
            content = _buildAtlasPreview(sprites, project, assets);
          } else {
            final definition = project.definitions[node.id];
            
            if (definition is SpriteDefinition) {
              _animationController.stop();
              final size = _getSpriteSize(project, definition, assets);
              contentSize = size ?? Size.zero;
              content = _buildSpritePreview(project, definition, assets, size);
            } else if (definition is AnimationDefinition) {
              // Pass Node, not just def
              _updateAnimationState(node, definition, previewState);
              
              // Use first child sprite for sizing
              if (node.children.isNotEmpty) {
                 final firstFrameDef = project.definitions[node.children.first.id];
                 if (firstFrameDef is SpriteDefinition) {
                   contentSize = _getSpriteSize(project, firstFrameDef, assets) ?? Size.zero;
                 }
              }
              content = _buildAnimationPreview(project, node, assets, contentSize);
            } else {
              content = _buildPlaceholder('No Data', 'Item definition missing.');
            }
          }
        }

        return LayoutBuilder(
          builder: (context, constraints) {
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
                      child: CustomPaint(
                        painter: _BackgroundPainter(settings: settings),
                      ),
                    ),
                  InteractiveViewer(
                    transformationController: _transformationController,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.01,
                    maxScale: 20.0,
                    child: contentSize.isEmpty 
                      ? Center(child: content) 
                      : Align(
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
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  Size? _getSpriteSize(TexturePackerProject project, SpriteDefinition def, Map<String, AssetData> assets) {
    final sourceConfig = _findSourceConfig(project.sourceImagesRoot, def.sourceImageId);
    if (sourceConfig == null) return null;
    
    final rect = _calculateSourceRect(sourceConfig, def.gridRect);
    return Size(rect.width, rect.height);
  }

  Widget _buildSpritePreview(
    TexturePackerProject project,
    SpriteDefinition spriteDef,
    Map<String, AssetData> assets,
    Size? precalcSize,
  ) {
    final sourceConfig = _findSourceConfig(project.sourceImagesRoot, spriteDef.sourceImageId);
    if (sourceConfig == null) return const Icon(Icons.broken_image);

    final asset = assets[sourceConfig.path];
    if (asset is! ImageAssetData) return const Icon(Icons.broken_image);

    final srcRect = _calculateSourceRect(sourceConfig, spriteDef.gridRect);
    final size = precalcSize ?? Size(srcRect.width, srcRect.height);

    return CustomPaint(
      size: size,
      painter: _SpritePainter(image: asset.image, srcRect: srcRect),
    );
  }

  Widget _buildAnimationPreview(
    TexturePackerProject project,
    PackerItemNode animNode,
    Map<String, AssetData> assets,
    Size frameSize,
  ) {
    if (_frameAnimation == null || animNode.children.isEmpty) {
      return _buildPlaceholder('Empty Animation', 'No frames (sprites) inside.');
    }

    var frameIndex = _frameAnimation!.value;
    // Safety check
    if (frameIndex >= animNode.children.length) frameIndex = 0;

    final frameNode = animNode.children[frameIndex];
    final spriteDef = project.definitions[frameNode.id] as SpriteDefinition?;

    if (spriteDef == null) return const Icon(Icons.error_outline);
    
    return _buildSpritePreview(project, spriteDef, assets, frameSize);
  }

  Widget _buildAtlasPreview(
    List<SpriteDefinition> sprites,
    TexturePackerProject project,
    Map<String, AssetData> assets,
  ) {
    if (sprites.isEmpty) return _buildPlaceholder('Empty Folder', 'No sprites to display.');

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: sprites.map((def) {
        final size = _getSpriteSize(project, def, assets);
        return Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.white24)),
          child: _buildSpritePreview(project, def, assets, size),
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(message),
      ],
    );
  }
}

// ... _BackgroundPainter and _SpritePainter remain unchanged ...
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
  bool shouldRepaint(_SpritePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.srcRect != srcRect;
  }
}