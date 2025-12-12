import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_settings.dart'; // Import settings
import 'package:machine/settings/settings_notifier.dart';

class SlicingView extends ConsumerWidget {
  final String tabId;
  final TexturePackerNotifier notifier;
  final TransformationController transformationController;
  final GridRect? dragSelection;
  final bool isPanZoomMode;
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
    final activeIndex = ref.watch(activeSourceImageIndexProvider);
    final project = notifier.project;
    
    // Read settings
    final settings = ref.watch(effectiveSettingsProvider
        .select((s) => s.pluginSettings[TexturePackerSettings] as TexturePackerSettings?)) 
        ?? TexturePackerSettings();

    if (activeIndex >= project.sourceImages.length) {
      return const Center(child: Text('Select a source image.'));
    }

    final sourceConfig = project.sourceImages[activeIndex];
    final assetMap = ref.watch(assetMapProvider(tabId));

    return assetMap.when(
      data: (assets) {
        final imageAsset = assets[sourceConfig.path];
        if (imageAsset is! ImageAssetData) {
          return Center(child: Text('Could not load image: ${sourceConfig.path}'));
        }

        final image = imageAsset.image;
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());

        final selectedNodeId = ref.watch(selectedNodeIdProvider);
        final definition = project.definitions[selectedNodeId];
        GridRect? activeSelection;
        if (definition is SpriteDefinition && definition.sourceImageIndex == activeIndex) {
          activeSelection = definition.gridRect;
        }

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
                child: CustomPaint(
                  size: imageSize,
                  painter: _SlicingPainter(
                    image: image,
                    slicing: sourceConfig.slicing,
                    dragSelection: dragSelection,
                    activeSelection: activeSelection,
                    settings: settings, // Pass settings
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
    // 1. Draw checkerboard background strictly within image bounds
    _drawCheckerboard(canvas, size);

    // 2. Draw the source image
    final imagePaint = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImage(image, Offset.zero, imagePaint);

    // 3. Draw the grid
    _drawGrid(canvas, size);

    // 4. Draw active selection
    if (activeSelection != null) {
      final paint = Paint()..color = Colors.green.withOpacity(0.5);
      _drawHighlight(canvas, activeSelection!, paint);
    }

    // 5. Draw drag selection
    if (dragSelection != null) {
      final paint = Paint()..color = Colors.blue.withOpacity(0.5);
      _drawHighlight(canvas, dragSelection!, paint);
    }
  }
  
  void _drawHighlight(Canvas canvas, GridRect rect, Paint paint) {
    final pixelRect = _gridToPixelRect(rect);
    canvas.drawRect(pixelRect, paint);
    
    // Draw stroke
    final stroke = Paint()
      ..color = paint.color.withOpacity(1.0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(pixelRect, stroke);
  }

  Rect _gridToPixelRect(GridRect rect) {
    final left = slicing.margin + rect.x * (slicing.tileWidth + slicing.padding);
    final top = slicing.margin + rect.y * (slicing.tileHeight + slicing.padding);
    // Width calculation: (width in tiles * tile width) + (number of gaps * padding)
    final width = rect.width * slicing.tileWidth + (rect.width - 1) * slicing.padding;
    final height = rect.height * slicing.tileHeight + (rect.height - 1) * slicing.padding;
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }

  void _drawGrid(Canvas canvas, Size size) {
    if (slicing.tileWidth <= 0 || slicing.tileHeight <= 0) return;

    final paint = Paint()
      ..color = Color(settings.gridColor)
      ..strokeWidth = settings.gridThickness;

    // Grid calculations should stop at the image edge
    final double endX = size.width;
    final double endY = size.height;

    // Vertical lines
    // Start at margin, jump by (tileWidth + padding)
    for (double x = slicing.margin.toDouble(); x <= endX; x += (slicing.tileWidth + slicing.padding)) {
      canvas.drawLine(Offset(x, 0), Offset(x, endY), paint);
      // If there is padding, draw the other side of the gutter
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
    // Only draw within image dimensions
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
        oldDelegate.settings != settings; // Check settings
  }
}