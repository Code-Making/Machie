import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' hide StringProperty;
import 'package:flutter/material.dart' hide StringProperty;
import 'package:tiled/tiled.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'tiled_editor_settings_model.dart';
import '../../../asset_cache/asset_models.dart';
import 'package:path/path.dart' as p;
import 'tiled_asset_resolver.dart';

class TiledMapPainter extends CustomPainter {
  final TiledMap map;
  final TiledAssetResolver resolver;
  final bool showGrid;
  final Matrix4 transform;
  
  final List<TiledObject> selectedObjects;
  final Rect? previewShape;
  final List<Point> inProgressPoints;
  final Rect? marqueeSelection;
  final TiledEditorSettings settings;
  final List<List<Gid>>? floatingSelection;
  final Point? floatingSelectionPosition;


  final Map<int, TextPainter> _textPainterCache = {};

  TiledMapPainter({
    required this.map,
    required this.resolver,
    required this.showGrid,
    required this.transform,
    this.selectedObjects = const [],
    this.previewShape,
    this.inProgressPoints = const [],
    this.marqueeSelection,
    required this.settings,
    this.floatingSelection,
    this.floatingSelectionPosition,
  });
  

  @override
  void paint(Canvas canvas, Size size) {
    final visibleRect = canvas.getDestinationClipBounds();
    
    _paintLayerGroup(canvas, map.layers, 1.0, visibleRect);
    if (floatingSelection != null && floatingSelectionPosition != null) {
      _paintFloatingSelection(canvas);
    }

    _paintObjectPreviews(canvas);

    if (showGrid) {
      final startX = (visibleRect.left / map.tileWidth - 1).floor().clamp(0, map.width);
      final startY = (visibleRect.top / map.tileHeight - 1).floor().clamp(0, map.height);
      final endX = (visibleRect.right / map.tileWidth + 1).ceil().clamp(0, map.width);
      final endY = (visibleRect.bottom / map.tileHeight + 1).ceil().clamp(0, map.height);
      _paintGrid(canvas, startX, startY, endX, endY);
    }
  }
  
  /// Legacy lookup: scans ALL loaded assets for a sprite name.
  /// Used for the old 'tp_sprite' property.
  TexturePackerSpriteData? _findLegacySpriteData(String spriteName) {
    for (final asset in resolver.rawAssets.values) {
      if (asset is TexturePackerAssetData) {
        if (asset.frames.containsKey(spriteName)) {
          return asset.frames[spriteName];
        }
        if (asset.animations.containsKey(spriteName)) {
          final firstFrame = asset.animations[spriteName]!.firstOrNull;
          if (firstFrame != null && asset.frames.containsKey(firstFrame)) {
            return asset.frames[firstFrame];
          }
        }
      }
    }
    return null;
  }

  /// Schema lookup: Uses the object's 'atlas' property to find the specific file,
  /// then looks for 'initialFrame' or 'initialAnim'.
  TexturePackerSpriteData? _findSchemaSpriteData(TiledObject object) {
    // 1. Check for file property
    final atlasProp = object.properties['atlas'];
    if (atlasProp is! StringProperty || atlasProp.value.isEmpty) return null;

    // 2. Check for frame/anim property
    final frameProp = object.properties['initialFrame'] ?? object.properties['initialAnim'];
    if (frameProp is! StringProperty || frameProp.value.isEmpty) return null;

    // 3. Resolve the specific asset
    // The atlas property is relative to the TMX file (e.g. "../atlases/chars.tpacker")
    final canonicalKey = resolver.repo.resolveRelativePath(resolver.tmxPath, atlasProp.value);
    final asset = resolver.getAsset(canonicalKey);

    if (asset is! TexturePackerAssetData) return null;

    // 4. Find the sprite within that asset
    final spriteName = frameProp.value;
    
    // Direct frame match
    if (asset.frames.containsKey(spriteName)) {
      return asset.frames[spriteName];
    }
    
    // Animation match (get first frame)
    if (asset.animations.containsKey(spriteName)) {
      final firstFrame = asset.animations[spriteName]!.firstOrNull;
      if (firstFrame != null && asset.frames.containsKey(firstFrame)) {
        return asset.frames[firstFrame];
      }
    }

    return null;
  }
  
  void _paintFloatingSelection(Canvas canvas) {
    final selection = floatingSelection!;
    final position = floatingSelectionPosition!;
    
    final Map<ui.Image, List<RSTransform>> transforms = {};
    final Map<ui.Image, List<Rect>> rects = {};

    for (int y = 0; y < selection.length; y++) {
      for (int x = 0; x < selection[y].length; x++) {
        final gid = selection[y][x];
        if (gid.tile == 0) continue;

        final tile = map.tileByGid(gid.tile);
        if (tile == null || tile.isEmpty) continue;
        
        final tileset = map.tilesetByTileGId(gid.tile);
        final imageSource = tile.image?.source ?? tileset.image?.source;
        if (imageSource == null) continue;

    final image = resolver.getImage(imageSource, tileset: tileset);
        if (image == null) continue;

        final srcRect = tileset.computeDrawRect(tile);
        final source = Rect.fromLTWH(srcRect.left.toDouble(), srcRect.top.toDouble(), srcRect.width.toDouble(), srcRect.height.toDouble());
        final tileWidth = (tileset.tileWidth ?? map.tileWidth).toDouble();
        final tileHeight = (tileset.tileHeight ?? map.tileHeight).toDouble();

        final dst = Rect.fromLTWH(
          ((position.x + x) * map.tileWidth).toDouble(),
          ((position.y + y) * map.tileHeight).toDouble() + map.tileHeight - tileHeight,
          tileWidth,
          tileHeight,
        );

        final transform = RSTransform.fromComponents(
            rotation: 0.0, scale: 1.0, anchorX: 0, anchorY: 0,
            translateX: dst.left, translateY: dst.top);
        
        transforms.putIfAbsent(image, () => []).add(transform);
        rects.putIfAbsent(image, () => []).add(source);
      }
    }
    
    final paint = Paint()..filterQuality = FilterQuality.none;
    for (final image in transforms.keys) {
      canvas.drawAtlas(image, transforms[image]!, rects[image]!, null, BlendMode.src, null, paint);
    }
    
    final selectionRect = Rect.fromLTWH(
      (position.x * map.tileWidth).toDouble(),
      (position.y * map.tileHeight).toDouble(),
      (selection.isNotEmpty ? selection[0].length : 0) * map.tileWidth.toDouble(),
      selection.length * map.tileHeight.toDouble(),
    );
    final borderPaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(selectionRect, borderPaint);
  }
  
  void _paintObjectPreviews(Canvas canvas) {
    if (selectedObjects.isNotEmpty) {
      final paint = Paint()
        ..color = Colors.blue.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      for (final obj in selectedObjects) {
        final rect = Rect.fromLTWH(obj.x, obj.y, obj.width, obj.height);
        canvas.drawRect(rect, paint);
        canvas.drawRect(rect, strokePaint);
      }
    }
    
    if (marqueeSelection != null) {
      final paint = Paint()
        ..color = Colors.blue.withOpacity(0.2)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.blue.withOpacity(0.8)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(marqueeSelection!, paint);
      canvas.drawRect(marqueeSelection!, strokePaint);
    }

    if (inProgressPoints.isNotEmpty) {
      final paint = Paint()
        ..color = Colors.amber
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo(inProgressPoints.first.x, inProgressPoints.first.y);
      for (var i = 1; i < inProgressPoints.length; i++) {
        path.lineTo(inProgressPoints[i].x, inProgressPoints[i].y);
      }
      canvas.drawPath(path, paint);
    }

    if (previewShape != null) {
      final paint = Paint()
        ..color = Colors.amber.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      canvas.drawRect(previewShape!, paint);
    }
  }

  void _paintLayerGroup(Canvas canvas, List<Layer> layers, double parentOpacity, Rect visibleRect) {
    for (final layer in layers) {
      if (!layer.visible) continue;

      final combinedOpacity = parentOpacity * layer.opacity;

      canvas.save();

      if (combinedOpacity < 1.0) {
        final paint = Paint()..color = Color.fromRGBO(0, 0, 0, combinedOpacity);
        canvas.saveLayer(visibleRect, paint);
      }
      
      if (layer is Group) {
        canvas.translate(layer.offsetX, layer.offsetY);
        _paintLayerGroup(canvas, layer.layers, combinedOpacity, visibleRect);
      } else {
        if (layer is TileLayer) {
          canvas.translate(layer.offsetX, layer.offsetY);
          _paintTileLayer(canvas, layer);
        } else if (layer is ImageLayer) {
          _paintImageLayer(canvas, layer, visibleRect);
        } else if (layer is ObjectGroup) {
          canvas.translate(layer.offsetX, layer.offsetY);
          _paintObjectGroup(canvas, layer);
        }
      }

      if (combinedOpacity < 1.0) {
        canvas.restore();
      }
      canvas.restore();
    }
  }

  void _paintGrid(Canvas canvas, int startX, int startY, int endX, int endY) {
    final paint = Paint()
      ..color = Color(settings.gridColorValue)
      ..strokeWidth = settings.gridThickness;

    for (var x = startX; x <= endX; x++) {
      final lineX = (x * map.tileWidth).toDouble();
      canvas.drawLine(
        Offset(lineX, startY * map.tileHeight.toDouble()),
        Offset(lineX, endY * map.tileHeight.toDouble()),
        paint,
      );
    }
    for (var y = startY; y <= endY; y++) {
      final lineY = (y * map.tileHeight).toDouble();
      canvas.drawLine(
        Offset(startX * map.tileWidth.toDouble(), lineY),
        Offset(endX * map.tileWidth.toDouble(), lineY),
        paint,
      );
    }
  }

  void _paintTileLayer(Canvas canvas, TileLayer layer) {
    // ... existing tile layer painting logic ...
    // (Kept brief for this response as it wasn't modified)
    final visibleRect = canvas.getDestinationClipBounds();
    final startX = (visibleRect.left / map.tileWidth - 1).floor().clamp(0, layer.width);
    final startY = (visibleRect.top / map.tileHeight - 1).floor().clamp(0, layer.height);
    final endX = (visibleRect.right / map.tileWidth + 1).ceil().clamp(0, layer.width);
    final endY = (visibleRect.bottom / map.tileHeight + 1).ceil().clamp(0, layer.height);

    if (layer.tileData == null) return;

    final Map<ui.Image, List<RSTransform>> transforms = {};
    final Map<ui.Image, List<Rect>> rects = {};

    for (var y = startY; y < endY; y++) {
      for (var x = startX; x < endX; x++) {
        if (x >= layer.width || y >= layer.height) continue;
        final gid = layer.tileData![y][x];
        if (gid.tile == 0) continue;

        final tile = map.tileByGid(gid.tile);
        if (tile == null || tile.isEmpty) continue;

        final tileset = map.tilesetByTileGId(gid.tile);
        final imageSource = tile.image?.source ?? tileset.image?.source;
        if (imageSource == null) continue;
        final image = resolver.getImage(imageSource, tileset: tileset);
        
        final srcRect = tileset.computeDrawRect(tile);
        final source = Rect.fromLTWH(
          srcRect.left.toDouble(),
          srcRect.top.toDouble(),
          srcRect.width.toDouble(),
          srcRect.height.toDouble(),
        );

        final tileWidth = (tileset.tileWidth ?? map.tileWidth).toDouble();
        final tileHeight = (tileset.tileHeight ?? map.tileHeight).toDouble();

        final dst = Rect.fromLTWH(
          (x * map.tileWidth).toDouble(),
          (y * map.tileHeight).toDouble() + map.tileHeight - tileHeight,
          tileWidth,
          tileHeight,
        );
        
        if (image == null) {
          _drawMissingImagePlaceholder(canvas, dst, imageSource ?? 'Unknown');
          continue;
        }

        final needsFlip = gid.flips.horizontally || gid.flips.vertically || gid.flips.diagonally;

        if (!needsFlip) {
          transforms.putIfAbsent(image, () => []);
          rects.putIfAbsent(image, () => []);
          
          final transform = RSTransform.fromComponents(
            rotation: 0.0,
            scale: 1.0,
            anchorX: 0,
            anchorY: 0,
            translateX: dst.left,
            translateY: dst.top,
          );
          
          transforms[image]!.add(transform);
          rects[image]!.add(source);

        } else {
          canvas.save();
          canvas.translate(dst.left + dst.width / 2, dst.top + dst.height / 2);

          if (gid.flips.diagonally) {
            canvas.transform(Float64List.fromList([0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
          }
          if (gid.flips.horizontally) {
            canvas.scale(-1.0, 1.0);
          }
          if (gid.flips.vertically) {
            canvas.scale(1.0, -1.0);
          }
          
          canvas.translate(-dst.width / 2, -dst.height / 2);
          
          canvas.drawImageRect(
            image,
            source,
            Rect.fromLTWH(0, 0, dst.width, dst.height),
            Paint()..filterQuality = FilterQuality.none,
          );
          canvas.restore();
        }
        
        if (tile.objectGroup != null && tile.objectGroup is ObjectGroup) {
          final collisionGroup = tile.objectGroup as ObjectGroup;
          canvas.save();
          canvas.translate(dst.left, dst.top);
          _paintObjectGroup(canvas, collisionGroup, isForTile: true);
          canvas.restore();
        }
      }
    }
    
    final paint = Paint()..filterQuality = FilterQuality.none;
    for (final image in transforms.keys) {
      canvas.drawAtlas(
        image,
        transforms[image]!,
        rects[image]!,
        null,
        BlendMode.src,
        null,
        paint,
      );
    }
  }
  
  void _paintImageLayer(Canvas canvas, ImageLayer layer, Rect visibleRect) {
    // ... existing image layer painting logic ...
    if (layer.image.source == null) return;
    final image = resolver.getImage(layer.image.source); 

    if (image == null) {
        _drawMissingImagePlaceholder(canvas, Rect.fromLTWH(layer.offsetX, layer.offsetY, (layer.image.width ?? 100).toDouble(), (layer.image.height ?? 100).toDouble()), layer.image.source ?? 'Unknown');
        return;
    }

    final invertedMatrix = Matrix4.tryInvert(transform);
    if (invertedMatrix == null) return;
    
    final totalOffsetX = layer.offsetX ;
    final totalOffsetY = - layer.offsetY ;

    final scaleX = (layer.image.width ?? image.width) / image.width;
    final scaleY = (layer.image.height ?? image.height) / image.height;
    
    final offsetMatrix = Matrix4.identity()
    ..translate(totalOffsetX, totalOffsetY)
    ..scale(scaleX, scaleY, 1);
    
    final matrix = Matrix4.copy(invertedMatrix)
    ..multiply(transform)
    ..multiply(offsetMatrix);

    final shader = ImageShader(
      image,
      layer.repeatX ? TileMode.repeated : TileMode.clamp,
      layer.repeatY ? TileMode.repeated : TileMode.clamp,
      matrix.storage,
    );

    final paint = Paint()
      ..shader = shader
      ..filterQuality = FilterQuality.none;

    canvas.drawPaint(paint);
  }
  
  // ... Matrix4 applyParallax() helper ... (kept from previous file)

  void _paintObjectGroup(Canvas canvas, ObjectGroup layer, {bool isForTile = false}) {
    final paint = isForTile
        ? (Paint()..color = Colors.lightGreen.withOpacity(0.5))
        : (Paint()..color = layer.color.toFlutterColor().withOpacity(0.5));
    paint.style = PaintingStyle.fill;
    
    final strokePaint = isForTile
        ? (Paint()..color = Colors.lightGreen)
        : (Paint()..color = layer.color.toFlutterColor());
    strokePaint.style = PaintingStyle.stroke;
    strokePaint.strokeWidth = 2.0;

    var objects = layer.objects;
    if (layer.drawOrder == DrawOrder.topDown) {
      objects = List.from(layer.objects)..sort((a, b) => a.y.compareTo(b.y));
    }
    
    for (final object in objects) {
      if (!object.visible) continue;

      canvas.save();
      
      // Apply rotation
      if (object.rotation != 0) {
        canvas.translate(object.x + object.width / 2, object.y + object.height / 2);
        canvas.rotate(vector.radians(object.rotation));
        canvas.translate(-(object.x + object.width / 2), -(object.y + object.height / 2));
      }
      
      bool customDrawDone = false;
      TexturePackerSpriteData? spriteData;

      // 1. Check Legacy tp_sprite (Global lookup)
      final tpSpriteProp = object.properties['tp_sprite'];
      if (tpSpriteProp is StringProperty && tpSpriteProp.value.isNotEmpty) {
         spriteData = _findLegacySpriteData(tpSpriteProp.value);
      }

      // 2. Check Schema Sprite (Specific atlas lookup)
      if (spriteData == null) {
         spriteData = _findSchemaSpriteData(object);
      }

      // Draw the sprite if found
      if (spriteData != null) {
          final srcRect = spriteData.sourceRect;
          final dstRect = Rect.fromLTWH(object.x, object.y, object.width, object.height);
          
          final drawRect = (object.width == 0 && object.height == 0)
              ? Rect.fromLTWH(object.x, object.y - srcRect.height, srcRect.width, srcRect.height)
              : dstRect;

          canvas.drawImageRect(
            spriteData.sourceImage, 
            srcRect, 
            drawRect, 
            Paint()..filterQuality = ui.FilterQuality.none
          );
          
          if (selectedObjects.contains(object)) {
             final strokePaint = Paint()..color = Colors.blue ..style=PaintingStyle.stroke ..strokeWidth=2;
             canvas.drawRect(drawRect, strokePaint);
          }
          customDrawDone = true;
      }

      // Fallback Drawing
      if (!customDrawDone) {
        if (object.gid != null) {
          _paintTileObject(canvas, object);
        } else {
          if (object.isRectangle) {
            final rect = Rect.fromLTWH(object.x, object.y, object.width, object.height);
            canvas.drawRect(rect, paint);
            canvas.drawRect(rect, strokePaint);
          } else if (object.isPoint) {
            final rect = Rect.fromLTWH(object.x, object.y, object.width, object.height);
            canvas.drawRect(rect, paint);
            canvas.drawRect(rect, strokePaint);
            
            final crossPaint = strokePaint;
            final centerX = object.x + object.width / 2;
            final centerY = object.y + object.height / 2;
            
            canvas.drawLine(Offset(centerX, object.y), Offset(centerX, object.y + object.height), crossPaint);
            canvas.drawLine(Offset(object.x, centerY), Offset(object.x + object.width, centerY), crossPaint);
          } else if (object.isEllipse) {
            final rect = Rect.fromLTWH(object.x, object.y, object.width, object.height);
            canvas.drawOval(rect, paint);
            canvas.drawOval(rect, strokePaint);
          } else if (object.isPolygon || object.isPolyline) {
            final points = object.isPolygon ? object.polygon : object.polyline;
            if (points.isNotEmpty) {
              final path = Path();
              path.moveTo(object.x + points.first.x, object.y + points.first.y);
              for (var i = 1; i < points.length; i++) {
                path.lineTo(object.x + points[i].x, object.y + points[i].y);
              }
              if (object.isPolygon) {
                path.close();
                canvas.drawPath(path, paint);
              }
              canvas.drawPath(path, strokePaint);
            }
          }
        }
      }

      if (object.text != null) {
        _paintTextObject(canvas, object);
      }
      
      canvas.restore();
    }
  }

  void _paintTileObject(Canvas canvas, TiledObject object) {
    // ... existing logic ...
    final gid = Gid.fromInt(object.gid!);
    if (gid.tile == 0) return;

    final tile = map.tileByGid(gid.tile);
    if (tile == null || tile.isEmpty) return;

    final tileset = map.tilesetByTileGId(gid.tile);
    final imageSource = tile.image?.source ?? tileset.image?.source;
    if (imageSource == null) return;

    final image = resolver.getImage(imageSource, tileset: tileset);
    
    final rect = tileset.computeDrawRect(tile);
    final src = Rect.fromLTWH(
      rect.left.toDouble(), rect.top.toDouble(),
      rect.width.toDouble(), rect.height.toDouble(),
    );

    final dst = Rect.fromLTWH(object.x, object.y - object.height, object.width, object.height);
    
    if (image == null) {
      _drawMissingImagePlaceholder(canvas, dst, imageSource ?? 'Unknown');
      return;
    }

    canvas.save();
    canvas.translate(dst.left + dst.width / 2, dst.top + dst.height / 2);
    if (gid.flips.diagonally) canvas.transform(Float64List.fromList([0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    if (gid.flips.horizontally) canvas.scale(-1.0, 1.0);
    if (gid.flips.vertically) canvas.scale(1.0, -1.0);
    canvas.translate(-dst.width / 2, -dst.height / 2);

    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, dst.width, dst.height),
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();
  }

  void _paintTextObject(Canvas canvas, TiledObject object) {
    // ... existing logic ...
    final textInfo = object.text!;
    var painter = _textPainterCache[object.id];
    
    if (painter == null) {
      final textStyle = TextStyle(
        fontFamily: textInfo.fontFamily,
        fontSize: textInfo.pixelSize.toDouble(),
        color: textInfo.color.toFlutterColor(),
        fontWeight: textInfo.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: textInfo.italic ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (textInfo.underline) TextDecoration.underline,
          if (textInfo.strikeout) TextDecoration.lineThrough,
        ]),
      );

      painter = TextPainter(
        text: TextSpan(text: textInfo.text, style: textStyle),
        textAlign: textInfo.hAlign.toFlutterTextAlign(),
        textDirection: ui.TextDirection.ltr,
      )
      ..layout(maxWidth: object.width > 0 ? object.width : double.infinity);
      
      _textPainterCache[object.id] = painter;
    }

    double yOffset;
    switch(textInfo.vAlign) {
      case VAlign.center:
        yOffset = (object.height - painter.height) / 2;
        break;
      case VAlign.bottom:
        yOffset = object.height - painter.height;
        break;
      case VAlign.top:
      default:
        yOffset = 0;
        break;
    }

    painter.paint(canvas, Offset(object.x, object.y + yOffset));
  }

  @override
  bool shouldRepaint(covariant TiledMapPainter oldDelegate) {
    if (oldDelegate.transform != transform) {
      _textPainterCache.clear();
    }
    return true;
  }
  
  void _drawMissingImagePlaceholder(Canvas canvas, Rect destinationRect, String path) {
    final paint = Paint()..color = Colors.pink.withOpacity(0.8);
    canvas.drawRect(destinationRect, paint);

    final errorPaint = Paint()..color = Colors.white;
    canvas.drawLine(destinationRect.topLeft, destinationRect.bottomRight, errorPaint);
    canvas.drawLine(destinationRect.bottomLeft, destinationRect.topRight, errorPaint);
  }
}

extension on String {
  Color toFlutterColor() {
    var hex = replaceAll("#", "");
    if (hex.length == 6) {
      hex = "FF$hex";
    }
    if (hex.length == 8) {
      return Color(int.parse("0x$hex"));
    }
    return Colors.black;
  }
}

extension on ColorData {
  Color toFlutterColor() => Color.fromARGB(alpha, red, green, blue);
}

extension on HAlign {
  TextAlign toFlutterTextAlign() {
    switch(this) {
      case HAlign.center:
        return TextAlign.center;
      case HAlign.right:
        return TextAlign.right;
      case HAlign.justify:
        return TextAlign.justify;
      case HAlign.left:
      default:
        return TextAlign.left;
    }
  }
}