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
  AnimationDefinition? _currentAnimationDef;
  String? _lastSelectedNodeId;
  bool _needsFit = true;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(vsync: this);
    
    // Force repaint on every frame tick
    _animationController.addListener(() {
      setState(() {});
    });
    
    // Handle "Play Once" behavior: Stop and Rewind
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        final state = ref.read(previewStateProvider(widget.tabId));
        if (!state.isLooping) {
          // 1. Update UI state to "Paused"
          ref.read(previewStateProvider(widget.tabId).notifier).state = 
              state.copyWith(isPlaying: false);
          
          // 2. Rewind to frame 0
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

    final effectiveSpeed = animDef.speed * state.speedMultiplier;
    // Ensure duration is at least 1ms to avoid division by zero
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

  /// Calculates the matrix to fit the content within the viewport with a margin.
  void _fitContent(Size contentSize, Size viewportSize) {
    if (contentSize.isEmpty || viewportSize.isEmpty) return;

    final double margin = 32.0;
    final double availableW = viewportSize.width - margin * 2;
    final double availableH = viewportSize.height - margin * 2;

    // Determine scale to fit the *closest* dimension
    final double scaleX = availableW / contentSize.width;
    final double scaleY = availableH / contentSize.height;
    
    // Use the smaller scale to ensure it fits entirely, clamped to reasonable limits
    final double scale = math.min(scaleX, scaleY).clamp(0.1, 10.0); 

    // Calculate offset to center the scaled content in the viewport.
    // This assumes the content is positioned at (0,0) locally.
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
    
    // Check if selection changed to trigger a re-fit
    if (selectedNodeId != _lastSelectedNodeId) {
      _lastSelectedNodeId = selectedNodeId;
      _needsFit = true;
      // Stop animation when switching nodes to prevent ghosting or state bleeding
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
            // We don't auto-fit Folders/Atlas as their size is dynamic/unknown at build time
          } else {
            final definition = project.definitions[node.id];
            
            if (definition is SpriteDefinition) {
              _animationController.stop();
              // Calculate size for single sprite
              final size = _getSpriteSize(project, definition, assets);
              contentSize = size ?? Size.zero;
              content = _buildSpritePreview(project, definition, assets, size);
            } else if (definition is AnimationDefinition) {
              _updateAnimationState(definition, previewState);
              // Calculate size based on first frame (assuming consistent frame size)
              if (definition.frameIds.isNotEmpty) {
                 final firstFrameDef = project.definitions[definition.frameIds.first];
                 if (firstFrameDef is SpriteDefinition) {
                   contentSize = _getSpriteSize(project, firstFrameDef, assets) ?? Size.zero;
                 }
              }
              content = _buildAnimationPreview(project, definition, assets, contentSize);
            } else {
              content = _buildPlaceholder('No Data', 'Item definition missing.');
            }
          }
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // Apply Auto-Fit logic if we have a valid content size
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
                    // FIX: Use Align(topLeft) instead of Center.
                    // Center conflicts with our manual matrix calculations by adding an offset.
                    // Align(topLeft) ensures the content starts at (0,0) in viewport space,
                    // making our _fitContent translation math correct.
                    child: contentSize.isEmpty 
                      ? Center(child: content) // For Atlas/Folder, fall back to simple Center
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
    if (def.sourceImageIndex >= project.sourceImages.length) return null;
    final sourceConfig = project.sourceImages[def.sourceImageIndex];
    final rect = _calculateSourceRect(sourceConfig, def.gridRect);
    return Size(rect.width, rect.height);
  }

  Widget _buildSpritePreview(
    TexturePackerProject project,
    SpriteDefinition spriteDef,
    Map<String, AssetData> assets,
    Size? precalcSize,
  ) {
    if (spriteDef.sourceImageIndex >= project.sourceImages.length) return const Icon(Icons.broken_image);
    
    final sourceConfig = project.sourceImages[spriteDef.sourceImageIndex];
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
    AnimationDefinition animDef,
    Map<String, AssetData> assets,
    Size frameSize,
  ) {
    if (_frameAnimation == null || animDef.frameIds.isEmpty) {
      return _buildPlaceholder('Empty Animation', 'No frames defined.');
    }

    // Wrap frame index safely
    var frameIndex = _frameAnimation!.value;
    if (frameIndex >= animDef.frameIds.length) frameIndex = 0;

    final frameId = animDef.frameIds[frameIndex];
    final spriteDef = project.definitions[frameId] as SpriteDefinition?;

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
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
          ),
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
    // Return true if image source or cropping changes to trigger repaint
    return oldDelegate.image != image || oldDelegate.srcRect != srcRect;
  }
}