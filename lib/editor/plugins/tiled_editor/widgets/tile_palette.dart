// FILE: lib/editor/plugins/tiled_editor/widgets/tile_palette.dart

import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tiled/tiled.dart' hide Text;
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;
import 'package:path/path.dart' as p;

import 'package:machine/asset_cache/asset_models.dart';

class TilePalette extends StatefulWidget {
  final TiledMap map;
  final Map<String, AssetData> assetDataMap; 
  final Map<String, String> assetLookup; // <--- NEW FIELD
  final Tileset? selectedTileset;
  final Rect? selectedTileRect;
  final ValueChanged<Tileset?> onTilesetChanged;
  final ValueChanged<Rect?> onTileSelectionChanged;
  final VoidCallback onAddTileset;
  final ValueChanged<DragUpdateDetails>? onResize;
  final VoidCallback? onInspectSelectedTileset;
  final VoidCallback? onDeleteSelectedTileset;
  final VoidCallback? onClearUnusedTilesets;
  final String mapContextPath;

  const TilePalette({
    super.key,
    required this.map,
    required this.assetDataMap,
    required this.assetLookup, // <--- REQUIRED
    required this.selectedTileset,
    required this.selectedTileRect,
    required this.onTilesetChanged,
    required this.onTileSelectionChanged,
    required this.onAddTileset,
    this.onResize,
    this.onInspectSelectedTileset,
    this.onDeleteSelectedTileset,
    this.onClearUnusedTilesets,
    required this.mapContextPath,
  });

  @override
  State<TilePalette> createState() => _TilePaletteState();
}

class _TilePaletteState extends State<TilePalette> {
  late final TransformationController _transformationController;
  Offset? _dragStart;
  Offset? _lastDragPosition;
  Rect? _selectionRect;
  bool _isPanZoomMode = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void didUpdateWidget(covariant TilePalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedTileRect == null && _selectionRect != null) {
      setState(() => _selectionRect = null);
    }
    if (widget.selectedTileset != oldWidget.selectedTileset) {
      _transformationController.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDrag(Offset positionInContent, {bool isEnd = false}) {
    if (widget.selectedTileset == null) return;
    final tileset = widget.selectedTileset!;
    final tileWidth = (tileset.tileWidth ?? 0).toDouble();
    final tileHeight = (tileset.tileHeight ?? 0).toDouble();

    if (tileWidth == 0 || tileHeight == 0) return;
    if (_dragStart == null) return;

    final end = positionInContent;
    final startTileX = (_dragStart!.dx / tileWidth).floor();
    final startTileY = (_dragStart!.dy / tileHeight).floor();
    final endTileX = (end.dx / tileWidth).floor();
    final endTileY = (end.dy / tileHeight).floor();

    final left = (startTileX < endTileX ? startTileX : endTileX).toDouble();
    final top = (startTileY < endTileY ? startTileY : endTileY).toDouble();
    final width = ((startTileX - endTileX).abs() + 1).toDouble();
    final height = ((startTileY - endTileY).abs() + 1).toDouble();
    final newRect = Rect.fromLTWH(left, top, width, height);

    if (isEnd) {
      widget.onTileSelectionChanged(newRect);
    } else {
      setState(() => _selectionRect = newRect);
    }
  }

  void _handleTap(Offset positionInContent) {
    if (widget.selectedTileset == null) return;
    final tileset = widget.selectedTileset!;
    final tileWidth = (tileset.tileWidth ?? 0).toDouble();
    final tileHeight = (tileset.tileHeight ?? 0).toDouble();

    if (tileWidth <= 0 || tileHeight <= 0) return;

    final tileX = (positionInContent.dx / tileWidth).floor();
    final tileY = (positionInContent.dy / tileHeight).floor();

    final newSelection = Rect.fromLTWH(
      tileX.toDouble(),
      tileY.toDouble(),
      1,
      1,
    );

    if (widget.selectedTileRect == newSelection) {
      widget.onTileSelectionChanged(null);
    } else {
      widget.onTileSelectionChanged(newSelection);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTilesets = widget.map.tilesets.isNotEmpty;

    return Material(
      elevation: 4,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(8),
      ),
      child: Column(
        children: [
          if (widget.onResize != null)
            GestureDetector(
              onVerticalDragUpdate: widget.onResize,
              child: Container(
                width: double.infinity,
                height: 20,
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<Tileset?>(
                    value: widget.selectedTileset,
                    hint: const Text('Select a tileset'),
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items:
                        hasTilesets
                            ? widget.map.tilesets
                                .map(
                                  (ts) => DropdownMenuItem(
                                    value: ts,
                                    child: Text(
                                      ts.name ?? 'Unnamed',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList()
                            : [],
                    onChanged: (ts) {
                      widget.onTileSelectionChanged(null);
                      widget.onTilesetChanged(ts);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: 'Add New Tileset',
                  onPressed: widget.onAddTileset,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  tooltip: 'Delete Selected Tileset',
                  onPressed: widget.selectedTileset != null
                      ? widget.onDeleteSelectedTileset
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Tileset Properties',
                  onPressed: widget.selectedTileset != null
                      ? widget.onInspectSelectedTileset
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.layers_clear_outlined),
                  tooltip: 'Clear Unused Tilesets',
                  onPressed: hasTilesets ? widget.onClearUnusedTilesets : null,
                ),
                const SizedBox(width: 8),
                const VerticalDivider(width: 1, indent: 8, endIndent: 8),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _isPanZoomMode
                        ? Icons.pan_tool_outlined
                        : Icons.select_all_outlined,
                  ),
                  tooltip: _isPanZoomMode ? 'Pan/Zoom Mode' : 'Select Mode',
                  color:
                      _isPanZoomMode
                          ? Theme.of(context).colorScheme.primary
                          : null,
                  onPressed:
                      () => setState(() => _isPanZoomMode = !_isPanZoomMode),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _buildPaletteView(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteView() {
    if (widget.selectedTileset == null) {
      return const Center(child: Text('No tileset selected.'));
    }
    final tileset = widget.selectedTileset!;
    final imageSource = tileset.image?.source;
    if (imageSource == null) {
      return const Center(child: Text('Tileset has no image.'));
    }
    
    // FAST LOOKUP
    final canonicalKey = widget.assetLookup[imageSource];
    final asset = canonicalKey != null ? widget.assetDataMap[canonicalKey] : null;
    
    final ui.Image? image;
    if (asset is ImageAssetData) {
      image = asset.image;
    } else {
      image = null;
    }
    
    if (image == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            const Text('Image not found.'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: widget.onInspectSelectedTileset, 
              child: const Text('Fix Path'),
            )
          ],
        ),
      );
    }

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final currentSelection = _selectionRect ?? widget.selectedTileRect;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTapUp: (details) {
        if (_isPanZoomMode) return;
        final inv = Matrix4.copy(_transformationController.value)..invert();
        final vec = inv.transform3(
          Vector3(details.localPosition.dx, details.localPosition.dy, 0),
        );
        _handleTap(Offset(vec.x, vec.y));
      },
      onPanStart: (details) {
        if (_isPanZoomMode) return;
        final inv = Matrix4.copy(_transformationController.value)..invert();
        final vec = inv.transform3(
          Vector3(details.localPosition.dx, details.localPosition.dy, 0),
        );
        final positionInContent = Offset(vec.x, vec.y);
        _dragStart = positionInContent;
        _lastDragPosition = _dragStart;
        _handleDrag(_dragStart!, isEnd: false);
      },
      onPanUpdate: (details) {
        if (_isPanZoomMode) return;
        final inv = Matrix4.copy(_transformationController.value)..invert();
        final vec = inv.transform3(
          Vector3(details.localPosition.dx, details.localPosition.dy, 0),
        );
        final positionInContent = Offset(vec.x, vec.y);
        _lastDragPosition = positionInContent;
        _handleDrag(positionInContent);
      },
      onPanEnd: (details) {
        if (_isPanZoomMode) return;
        final endPosition = _lastDragPosition ?? _dragStart;
        if (endPosition != null) {
          _handleDrag(endPosition, isEnd: true);
        }
        _dragStart = null;
        _lastDragPosition = null;
      },
      child: InteractiveViewer(
        transformationController: _transformationController,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.1,
        maxScale: 8.0,
        panEnabled: _isPanZoomMode,
        scaleEnabled: _isPanZoomMode,
        child: CustomPaint(
          size: imageSize,
          painter: _TilesetPainter(
            image: image,
            tileset: tileset,
            selection: currentSelection,
          ),
        ),
      ),
    );
  }
}

class _TilesetPainter extends CustomPainter {
  final ui.Image image;
  final Tileset tileset;
  final Rect? selection;

  _TilesetPainter({required this.image, required this.tileset, this.selection});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.none);
    final tileWidth = (tileset.tileWidth ?? 0).toDouble();
    final tileHeight = (tileset.tileHeight ?? 0).toDouble();
    if (tileWidth == 0 || tileHeight == 0) return;
    final gridPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..strokeWidth = 0.5;
    for (double x = 0; x <= size.width; x += tileWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += tileHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (selection != null) {
      final selectionPaint =
          Paint()
            ..color = Colors.blue.withOpacity(0.5)
            ..style = PaintingStyle.fill;
      final pixelRect = Rect.fromLTWH(
        selection!.left * tileWidth,
        selection!.top * tileHeight,
        selection!.width * tileWidth,
        selection!.height * tileHeight,
      );
      canvas.drawRect(pixelRect, selectionPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TilesetPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.tileset != tileset ||
        oldDelegate.selection != selection;
  }
}