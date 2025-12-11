import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';

class SlicingView extends ConsumerWidget {
  final String tabId;
  final TexturePackerNotifier notifier; // Pass notifier directly
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
    final project = notifier.project; // Get project state from notifier

    if (activeIndex >= project.sourceImages.length) {
      return const Center(child: Text('Select a source image.'));
    }

    final sourceConfig = project.sourceImages[activeIndex];
    
    // --- ASSET LOADING REFACTOR ---
    // Watch the asset provider for the current tab.
    final assetMap = ref.watch(assetMapProvider(tabId));

    // Use .when() to handle loading, data, and error states gracefully.
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

        return GestureDetector(
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
                ),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading assets: $err')),
    );
    // --- END REFACTOR ---
  }
}

/// Custom painter for the slicing view.
/// This is a pure rendering widget with no business logic.
class _SlicingPainter extends CustomPainter {
  final ui.Image image;
  final SlicingConfig slicing;
  final GridRect? dragSelection;
  final GridRect? activeSelection;

  _SlicingPainter({
    required this.image,
    required this.slicing,
    this.dragSelection,
    this.activeSelection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw checkerboard background
    _drawCheckerboard(canvas, size);

    // 2. Draw the source image
    final imagePaint = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImage(image, Offset.zero, imagePaint);

    // 3. Draw the grid
    _drawGrid(canvas, size);

    // 4. Draw the active selection (from the hierarchy panel)
    if (activeSelection != null) {
      final paint = Paint()..color = Colors.green.withOpacity(0.5);
      _drawHighlight(canvas, activeSelection!, paint);
    }

    // 5. Draw the current drag selection
    if (dragSelection != null) {
      final paint = Paint()..color = Colors.blue.withOpacity(0.5);
      _drawHighlight(canvas, dragSelection!, paint);
    }
  }
  
  void _drawHighlight(Canvas canvas, GridRect rect, Paint paint) {
    final pixelRect = _gridToPixelRect(rect);
    canvas.drawRect(pixelRect, paint);
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
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.0;
      
    final faintPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1.0;

    final cellWidth = (slicing.tileWidth + slicing.padding).toDouble();
    final cellHeight = (slicing.tileHeight + slicing.padding).toDouble();

    final imageWidth = size.width;
    final imageHeight = size.height;

    for (double x = slicing.margin.toDouble(); x < imageWidth; x += cellWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, imageHeight), paint);
      if (slicing.padding > 0) {
        canvas.drawLine(Offset(x + slicing.tileWidth, 0), Offset(x + slicing.tileWidth, imageHeight), faintPaint);
      }
    }

    for (double y = slicing.margin.toDouble(); y < imageHeight; y += cellHeight) {
      canvas.drawLine(Offset(0, y), Offset(imageWidth, y), paint);
      if (slicing.padding > 0) {
        canvas.drawLine(Offset(0, y + slicing.tileHeight), Offset(imageWidth, y + slicing.tileHeight), faintPaint);
      }
    }
  }

  void _drawCheckerboard(Canvas canvas, Size size) {
    final checkerPaint1 = Paint()..color = const Color(0xFF404040);
    final checkerPaint2 = Paint()..color = const Color(0xFF505050);
    const double checkerSize = 16.0;
    for (double i = 0; i < size.width; i += checkerSize) {
      for (double j = 0; j < size.height; j += checkerSize) {
        final paint = ((i + j) / checkerSize) % 2 == 0 ? checkerPaint1 : checkerPaint2;
        canvas.drawRect(Rect.fromLTWH(i, j, checkerSize, checkerSize), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SlicingPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.slicing != slicing ||
        oldDelegate.dragSelection != dragSelection ||
        oldDelegate.activeSelection != activeSelection;
  }
}