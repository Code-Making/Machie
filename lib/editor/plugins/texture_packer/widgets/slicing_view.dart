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
    // 1. Checkerboard
    _drawCheckerboard(canvas, size);

    // 2. Source Image
    final imagePaint = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImage(image, Offset.zero, imagePaint);

    // 3. Grid Lines
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

  void _drawGrid(Canvas canvas, Size size) {
    if (slicing.tileWidth <= 0 || slicing.tileHeight <= 0) return;

    final paint = Paint()
      ..color = Color(settings.gridColor)
      ..strokeWidth = settings.gridThickness;

    final double endX = size.width;
    final double endY = size.height;

    // Vertical lines
    for (double x = slicing.margin.toDouble(); x <= endX; x += (slicing.tileWidth + slicing.padding)) {
      canvas.drawLine(Offset(x, 0), Offset(x, endY), paint);
      if (slicing.padding > 0) {
        final gutterRight = x + slicing.tileWidth;
        if (gutterRight <= endX) {
          canvas.drawLine(Offset(gutterRight, 0), Offset(gutterRight, endY), paint);
        }
      }
    }

    // Horizontal lines
    for (double y = slicing.margin.toDouble(); y <= endY; y += (slicing.tileHeight + slicing.padding)) {
      canvas.drawLine(Offset(0, y), Offset(endX, y), paint);
      if (slicing.padding > 0) {
        final gutterBottom = y + slicing.tileHeight;
        if (gutterBottom <= endY) {
          canvas.drawLine(Offset(0, gutterBottom), Offset(endX, gutterBottom), paint);
        }
      }
    }
  }

  void _drawCheckerboard(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.save();
    canvas.clipRect(rect);

    final c1 = Color(settings.checkerBoardColor1);
    final c2 = Color(settings.checkerBoardColor2);
    final paint = Paint();
    
    const double checkerSize = 16.0;
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
    canvas.restore();
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