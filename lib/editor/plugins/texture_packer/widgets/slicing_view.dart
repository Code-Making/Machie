import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart';

class SlicingView extends ConsumerStatefulWidget {
  final String tabId;
  const SlicingView({super.key, required this.tabId});

  @override
  ConsumerState<SlicingView> createState() => _SlicingViewState();
}

class _SlicingViewState extends ConsumerState<SlicingView> {
  late final TransformationController _transformationController;
  
  // State for tracking a drag-selection, in image pixel coordinates.
  Offset? _dragStart;
  // The current selection being dragged, in grid coordinates.
  GridRect? _selectionRect;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  /// Converts a pixel offset within the image to a 1x1 grid rect.
  GridRect? _pixelToGridRect(Offset position, SlicingConfig slicing) {
    if (position.dx < slicing.margin || position.dy < slicing.margin) return null;

    final effectiveX = position.dx - slicing.margin;
    final effectiveY = position.dy - slicing.margin;

    final cellWidth = slicing.tileWidth + slicing.padding;
    final cellHeight = slicing.tileHeight + slicing.padding;

    if (cellWidth <= 0 || cellHeight <= 0) return null;

    final gridX = (effectiveX / cellWidth).floor();
    final gridY = (effectiveY / cellHeight).floor();

    // Check if the click was in the padding area
    if (effectiveX % cellWidth > slicing.tileWidth) return null;
    if (effectiveY % cellHeight > slicing.tileHeight) return null;

    return GridRect(x: gridX, y: gridY, width: 1, height: 1);
  }

  /// Handles the start of a tap or drag gesture.
  void _onGestureStart(Offset localPosition, SlicingConfig slicing) {
    final invMatrix = Matrix4.copy(_transformationController.value)..invert();
    final positionInImage = MatrixUtils.transformPoint(invMatrix, localPosition);
    
    setState(() {
      _dragStart = positionInImage;
      _selectionRect = _pixelToGridRect(positionInImage, slicing);
    });
  }

  /// Handles the update of a drag gesture.
  void _onGestureUpdate(Offset localPosition, SlicingConfig slicing) {
    if (_dragStart == null) return;

    final invMatrix = Matrix4.copy(_transformationController.value)..invert();
    final positionInImage = MatrixUtils.transformPoint(invMatrix, localPosition);

    final startRect = _pixelToGridRect(_dragStart!, slicing);
    final endRect = _pixelToGridRect(positionInImage, slicing);

    if (startRect == null || endRect == null) return;
    
    final left = startRect.x < endRect.x ? startRect.x : endRect.x;
    final top = startRect.y < endRect.y ? startRect.y : endRect.y;
    final right = startRect.x > endRect.x ? startRect.x : endRect.x;
    final bottom = startRect.y > endRect.y ? startRect.y : endRect.y;
    
    setState(() {
      _selectionRect = GridRect(
        x: left,
        y: top,
        width: right - left + 1,
        height: bottom - top + 1,
      );
    });
  }

  /// Handles the end of a tap or drag, prompting to create a sprite.
  Future<void> _onGestureEnd() async {
    if (_selectionRect == null) return;
    
    final confirmedRect = _selectionRect!;
    // Reset local state immediately for snappy UI
    setState(() {
      _dragStart = null;
      _selectionRect = null;
    });

    final spriteName = await showTextInputDialog(context, title: 'Create New Sprite');
    if (spriteName != null && spriteName.trim().isNotEmpty) {
      final notifier = ref.read(texturePackerNotifierProvider(widget.tabId).notifier);
      final activeImageIndex = ref.read(activeSourceImageIndexProvider);

      // TODO: Get selected folder ID to create sprite inside it.
      // For now, it will be created at the root.
      final parentId = ref.read(selectedNodeIdProvider.select((id) {
        final nodeType = ref.read(texturePackerNotifierProvider(widget.tabId)
          .select((p) => p.definitions[id]?.runtimeType));
        // Only allow adding to folders or root
        return nodeType != SpriteDefinition && nodeType != AnimationDefinition ? id : null;
      }));
      
      final newNode = notifier.createNode(
        type: PackerItemType.sprite,
        name: spriteName.trim(),
        parentId: parentId,
      );

      final definition = SpriteDefinition(
        sourceImageIndex: activeImageIndex,
        gridRect: confirmedRect,
      );

      notifier.updateSpriteDefinition(newNode.id, definition);

      // Select the newly created node
      ref.read(selectedNodeIdProvider.notifier).state = newNode.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = ref.watch(activeSourceImageIndexProvider);
    final project = ref.watch(texturePackerNotifierProvider(widget.tabId));

    if (activeIndex >= project.sourceImages.length) {
      return const Center(child: Text('Select a source image.'));
    }

    final sourceConfig = project.sourceImages[activeIndex];
    final slicingConfig = sourceConfig.slicing;
    final assetMap = ref.watch(assetMapProvider(widget.tabId));

    return assetMap.when(
      data: (assets) {
        final imageAsset = assets[sourceConfig.path];
        if (imageAsset is! ImageAssetData) {
          return Center(child: Text('Could not load image: ${sourceConfig.path}'));
        }

        final image = imageAsset.image;
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());

        // Find the grid rect of the currently selected node, if any.
        final selectedNodeId = ref.watch(selectedNodeIdProvider);
        final definition = project.definitions[selectedNodeId];
        GridRect? activeSelection;
        if (definition is SpriteDefinition && definition.sourceImageIndex == activeIndex) {
          activeSelection = definition.gridRect;
        }

        return GestureDetector(
          onTapUp: (_) => _onGestureEnd(),
          onPanStart: (details) => _onGestureStart(details.localPosition, slicingConfig),
          onPanUpdate: (details) => _onGestureUpdate(details.localPosition, slicingConfig),
          onPanEnd: (_) => _onGestureEnd(),
          child: InteractiveViewer(
            transformationController: _transformationController,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.1,
            maxScale: 8.0,
            child: CustomPaint(
              size: imageSize,
              painter: _SlicingPainter(
                image: image,
                slicing: slicingConfig,
                dragSelection: _selectionRect,
                activeSelection: activeSelection,
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

/// Custom painter for the slicing view.
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

    final cellWidth = (slicing.tileWidth + slicing.padding).toDouble();
    final cellHeight = (slicing.tileHeight + slicing.padding).toDouble();

    final imageWidth = size.width;
    final imageHeight = size.height;

    for (double x = slicing.margin.toDouble(); x < imageWidth; x += cellWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, imageHeight), paint);
      if (slicing.padding > 0) {
        canvas.drawLine(Offset(x + slicing.tileWidth, 0), Offset(x + slicing.tileWidth, imageHeight), paint..color = Colors.white.withOpacity(0.15));
      }
    }

    for (double y = slicing.margin.toDouble(); y < imageHeight; y += cellHeight) {
      canvas.drawLine(Offset(0, y), Offset(imageWidth, y), paint..color = Colors.white.withOpacity(0.4));
      if (slicing.padding > 0) {
        canvas.drawLine(Offset(0, y + slicing.tileHeight), Offset(imageWidth, y + slicing.tileHeight), paint..color = Colors.white.withOpacity(0.15));
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