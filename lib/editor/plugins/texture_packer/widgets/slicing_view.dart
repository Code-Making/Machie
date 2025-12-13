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

class SlicingView extends ConsumerWidget {
  final String tabId;
  final TexturePackerNotifier notifier;
  final TransformationController transformationController;
  final GridRect? dragSelection;
  final bool isPanZoomMode;
  // Gestures pass the position back to the controller
  final Function(Offset localPosition) onGestureStart;
  final Function(Offset localPosition) onGestureUpdate;
  final VoidCallback onGestureEnd;

  const SlicingView({
    super.key,
    required this.tabId,
    required this.notifier,
    required this.transformationController,
    required this.dragSelection,
    required this.isPanZoomMode,
    required this.onGestureStart,
    required this.onGestureUpdate,
    required this.onGestureEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Get Active Source Image ID
    final activeSourceId = ref.watch(activeSourceImageIdProvider);
    
    // 2. Read Settings
    final settings = ref.watch(effectiveSettingsProvider
        .select((s) => s.pluginSettings[TexturePackerSettings] as TexturePackerSettings?)) 
        ?? TexturePackerSettings();

    if (activeSourceId == null) {
      return const Center(child: Text('Select a source image from the panel.'));
    }

    // 3. Find Configuration in Tree
    final sourceConfig = notifier.findSourceImageConfig(activeSourceId);
    if (sourceConfig == null) {
      return const Center(child: Text('Source image not found in hierarchy.'));
    }

    // 4. Load Asset
    final assetMap = ref.watch(assetMapProvider(tabId));

    return assetMap.when(
      data: (assets) {
        final imageAsset = assets[sourceConfig.path];
        
        if (imageAsset is ErrorAssetData) {
           return Center(child: Text('Failed to load image:\n${imageAsset.error}'));
        }
        
        if (imageAsset is! ImageAssetData) {
          // Still loading specific asset or not found in map yet
          return const Center(child: CircularProgressIndicator());
        }

        final image = imageAsset.image;
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());

        // 5. Determine Active Selection (Green Box)
        // We look at the selected OUTPUT node (Sprite). If it references this source, highlight it.
        final selectedNodeId = ref.watch(selectedNodeIdProvider);
        GridRect? activeSelection;
        
        if (selectedNodeId != null) {
          final definition = notifier.project.definitions[selectedNodeId];
          if (definition is SpriteDefinition && definition.sourceImageId == activeSourceId) {
            activeSelection = definition.gridRect;
          }
        }

        // 6. Build UI
        return SizedBox.expand(
          child: GestureDetector(
            onPanStart: (details) => onGestureStart(details.localPosition),
            onPanUpdate: (details) => onGestureUpdate(details.localPosition),
            onPanEnd: (_) => onGestureEnd(),
            child: Listener(
              onPointerUp: (_) => onGestureEnd(),
              child: InteractiveViewer(
                transformationController: transformationController,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.1,
                maxScale: 16.0,
                panEnabled: isPanZoomMode,
                scaleEnabled: isPanZoomMode,
                constrained: false, // <--- THE FIX: Allow content to be larger than viewport
                child: SizedBox(
                  width: imageSize.width,
                  height: imageSize.height,
                  child: CustomPaint(
                    size: imageSize,
                    painter: _SlicingPainter(
                      image: image,
                      slicing: sourceConfig.slicing,
                      dragSelection: dragSelection,
                      activeSelection: activeSelection,
                      settings: settings,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading assets: $err')),
    );
  }
}

class _SlicingPainter extends CustomPainter {
  final ui.Image image;
  final SlicingConfig slicing;
  final GridRect? dragSelection;
  final GridRect? activeSelection;
  final TexturePackerSettings settings;

  _SlicingPainter({
    required this.image,
    required this.slicing,
    this.dragSelection,
    this.activeSelection,
    required this.settings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Checkerboard (Background)
    _drawCheckerboard(canvas, size);

    // 2. Source Image
    final imagePaint = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImage(image, Offset.zero, imagePaint);

    // 3. Grid Lines (Overlay)
    _drawGrid(canvas, size);

    // 4. Highlights
    if (activeSelection != null) {
      final paint = Paint()..color = Colors.green.withOpacity(0.5);
      _drawHighlight(canvas, activeSelection!, paint);
    }

    if (dragSelection != null) {
      final paint = Paint()..color = Colors.blue.withOpacity(0.5);
      _drawHighlight(canvas, dragSelection!, paint);
    }
  }
  
  void _drawHighlight(Canvas canvas, GridRect rect, Paint paint) {
    final pixelRect = _gridToPixelRect(rect);
    canvas.drawRect(pixelRect, paint);
    
    final stroke = Paint()
      ..color = paint.color.withOpacity(1.0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(pixelRect, stroke);
  }

  Rect _gridToPixelRect(GridRect rect) {
    final left = slicing.margin + rect.x * (slicing.tileWidth + slicing.padding);
    final top = slicing.margin + rect.y * (slicing.tileHeight + slicing.padding);
    final width = rect.width * slicing.tileWidth + (rect.width - 1) * slicing.padding;
    final height = rect.height * slicing.tileHeight + (rect.height - 1) * slicing.padding;
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }

  // --- FIX 2: Correct Grid Shader Logic ---
  void _drawGrid(Canvas canvas, Size size) {
    if (slicing.tileWidth <= 0 || slicing.tileHeight <= 0) return;

    final double periodX = (slicing.tileWidth + slicing.padding).toDouble();
    final double periodY = (slicing.tileHeight + slicing.padding).toDouble();
    final double thickness = settings.gridThickness;
    final Color gridColor = Color(settings.gridColor);

    if (periodX <= 0 || periodY <= 0) return;

    final paint = Paint()..style = PaintingStyle.fill;

    // Helper to build stops for [Line]...[Space]...[Optional Line]
    List<Color> buildColors() {
      final c = [gridColor, gridColor, Colors.transparent, Colors.transparent];
      // If padding exists, add a second line at the end of the tile (start of gutter)
      if (slicing.padding > 0) {
        c.addAll([Colors.transparent, Colors.transparent, gridColor, gridColor, Colors.transparent, Colors.transparent]);
      }
      return c;
    }

    List<double> buildStops(double period, double tileDim) {
      final double r1 = (thickness / period).clamp(0.0, 1.0);
      final s = [0.0, r1, r1, 1.0];
      
      if (slicing.padding > 0) {
        // Line 2 starts after the tile content
        final double r2Start = (tileDim / period).clamp(0.0, 1.0);
        final double r2End = ((tileDim + thickness) / period).clamp(0.0, 1.0);
        
        // Insert second line stops in the middle
        return [
          0.0, r1, 
          r1, r2Start, 
          r2Start, r2End, 
          r2End, 1.0
        ];
      }
      return s;
    }

    // Vertical Lines Shader
    paint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(periodX, 0),
      buildColors(),
      buildStops(periodX, slicing.tileWidth.toDouble()),
      TileMode.repeated,
      Matrix4.translationValues(slicing.margin.toDouble(), 0, 0).storage,
    );
    canvas.drawRect(Offset.zero & size, paint);

    // Horizontal Lines Shader
    paint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, periodY),
      buildColors(),
      buildStops(periodY, slicing.tileHeight.toDouble()),
      TileMode.repeated,
      Matrix4.translationValues(0, slicing.margin.toDouble(), 0).storage,
    );
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawCheckerboard(Canvas canvas, Size size) {
    final c1 = Color(settings.checkerBoardColor1);
    final c2 = Color(settings.checkerBoardColor2);

    // Draw base color
    canvas.drawColor(c1, BlendMode.src);

    final paint = Paint()..color = c2;
    const double checkerSize = 16.0;

    // Batch draw the alternating squares using a Path
    final path = Path();
    final cols = (size.width / checkerSize).ceil();
    final rows = (size.height / checkerSize).ceil();

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        if ((x + y) % 2 == 1) {
          path.addRect(Rect.fromLTWH(
            x * checkerSize, 
            y * checkerSize, 
            checkerSize, 
            checkerSize
          ));
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SlicingPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.slicing != slicing ||
        oldDelegate.dragSelection != dragSelection ||
        oldDelegate.activeSelection != activeSelection ||
        oldDelegate.settings != settings;
  }
}