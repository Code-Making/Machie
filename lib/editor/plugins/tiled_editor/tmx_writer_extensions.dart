import 'package:tiled/tiled.dart';
import 'package:xml/xml.dart';

// Helper to convert ColorData to and from Hex strings.
ColorData _colorDataFromHex(String hex) {
  var source = hex.replaceAll('#', '');
  if (source.length == 6) { source = 'ff$source'; }
  if (source.length == 8) {
    final val = int.parse(source, radix: 16);
    return ColorData.hex(val);
  }
  return const ColorData.argb(255, 0, 0, 0);
}

extension on ColorData {
  String toHex({String prefix = '#', bool includeAlpha = true}) {
    final r = red.toRadixString(16).padLeft(2, '0');
    final g = green.toRadixString(16).padLeft(2, '0');
    final b = blue.toRadixString(16).padLeft(2, '0');
    if (includeAlpha) {
      final a = alpha.toRadixString(16).padLeft(2, '0');
      return '$prefix$a$r$g$b';
    }
    return '$prefix$r$g$b';
  }
}

// --- Main Writer Extensions ---

extension TiledMapWriter on TiledMap {
  void writeTo(XmlBuilder builder) {
    builder.element('map', nest: () {
      builder.attribute('version', version);
      if (tiledVersion != null) builder.attribute('tiledversion', tiledVersion!);
      if (orientation != null) builder.attribute('orientation', orientation!.name);
      builder.attribute('renderorder', renderOrder.name.replaceAll(RegExp(r'(?=[A-Z])'), '-').toLowerCase());
      builder.attribute('width', width);
      builder.attribute('height', height);
      builder.attribute('tilewidth', tileWidth);
      builder.attribute('tileheight', tileHeight);
      builder.attribute('infinite', infinite ? '1' : '0');
      if (nextLayerId != null) builder.attribute('nextlayerid', nextLayerId!);
      if (nextObjectId != null) builder.attribute('nextobjectid', nextObjectId!);
      if (backgroundColorHex != null) builder.attribute('backgroundcolor', backgroundColorHex!);

      properties.writeTo(builder);

      for (final tileset in tilesets) {
        tileset.writeTo(builder);
      }
      for (final layer in layers) {
        layer.writeTo(builder);
      }
    });
  }
}

extension TilesetWriter on Tileset {
  void writeTo(XmlBuilder builder) {
    builder.element('tileset', nest: () {
      if (firstGid != null) builder.attribute('firstgid', firstGid!);
      
      if (source != null) {
        builder.attribute('source', source!);
      } else {
        if (name != null) builder.attribute('name', name!);
        if (tileWidth != null) builder.attribute('tilewidth', tileWidth!);
        if (tileHeight != null) builder.attribute('tileheight', tileHeight!);
        if (spacing != 0) builder.attribute('spacing', spacing);
        if (margin != 0) builder.attribute('margin', margin);
        if (tileCount != null) builder.attribute('tilecount', tileCount!);
        if (columns != null) builder.attribute('columns', columns!);

        image?.writeTo(builder);

        for (final tile in tiles) {
          tile.writeTo(builder);
        }
      }
    });
  }
}

extension TiledImageWriter on TiledImage {
  void writeTo(XmlBuilder builder) {
    builder.element('image', nest: () {
      builder.attribute('source', source!);
      if (width != null) builder.attribute('width', width!);
      if (height != null) builder.attribute('height', height!);
    });
  }
}

extension TileWriter on Tile {
  void writeTo(XmlBuilder builder) {
    if (properties.isNotEmpty || animation.isNotEmpty || objectGroup != null) {
      builder.element('tile', nest: () {
        builder.attribute('id', localId);
        properties.writeTo(builder);
        
        if (animation.isNotEmpty) {
          builder.element('animation', nest: () {
            for (final frame in animation) {
              frame.writeTo(builder);
            }
          });
        }
        
        objectGroup?.writeTo(builder, isForTile: true);
      });
    }
  }
}

extension FrameWriter on Frame {
  void writeTo(XmlBuilder builder) {
    builder.element('frame', nest: () {
      builder.attribute('tileid', tileId);
      builder.attribute('duration', duration);
    });
  }
}

extension LayerWriter on Layer {
  void writeTo(XmlBuilder builder,  {bool isForTile = false}) {
    final layer = this;
    if (layer is TileLayer) {
      layer.writeTo(builder);
    } else if (layer is ObjectGroup) {
      // --- FIX 1: Pass the named parameter correctly. ---
      layer.writeTo(builder, isForTile: isForTile);
    } else if (layer is ImageLayer) {
      layer.writeTo(builder);
    } else if (layer is Group) {
      layer.writeTo(builder);
    }
  }

  void _writeCommonAttributes(XmlBuilder builder) {
    if (id != null) builder.attribute('id', id!);
    builder.attribute('name', name);
    if (class_ != null && class_!.isNotEmpty) builder.attribute('class', class_!);
    if (offsetX != 0) builder.attribute('offsetx', offsetX);
    if (offsetY != 0) builder.attribute('offsety', offsetY);
    if (opacity < 1) builder.attribute('opacity', opacity);
    if (!visible) builder.attribute('visible', '0');
    if (tintColorHex != null) builder.attribute('tintcolor', tintColorHex!);
  }
}

extension TileLayerWriter on TileLayer {
  void writeTo(XmlBuilder builder) {
    builder.element('layer', nest: () {
      _writeCommonAttributes(builder);
      builder.attribute('width', width);
      builder.attribute('height', height);
      properties.writeTo(builder);

      builder.element('data', nest: () {
        builder.attribute('encoding', 'csv');
        final gids = <int>[];

        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            Gid gid;
            if (tileData != null && y < tileData!.length && x < tileData![y].length) {
              gid = tileData![y][x];
            } else {
              gid = Gid.fromInt(0);
            }
            
            int outputGid = gid.tile;
            if (gid.flips.horizontally) outputGid |= Gid.flippedHorizontallyFlag;
            if (gid.flips.vertically) outputGid |= Gid.flippedVerticallyFlag;
            if (gid.flips.diagonally) outputGid |= Gid.flippedDiagonallyFlag;
            gids.add(outputGid);
          }
        }
        builder.text('\n${gids.join(',')}\n');
      });
    });
  }
}

extension ObjectGroupWriter on ObjectGroup {
  void writeTo(XmlBuilder builder, {required bool isForTile}) {
    builder.element('objectgroup', nest: () {
      if (!isForTile) {
        _writeCommonAttributes(builder);
        if (drawOrder != null) {
          builder.attribute('draworder', drawOrder!.name.replaceAll('Order', ''));
        }
      }
      properties.writeTo(builder);

      for (final object in objects) {
        object.writeTo(builder);
      }
    });
  }
}

extension ImageLayerWriter on ImageLayer {
  void writeTo(XmlBuilder builder) {
    builder.element('imagelayer', nest: () {
      _writeCommonAttributes(builder);
      if (repeatX) builder.attribute('repeatx', '1');
      if (repeatY) builder.attribute('repeaty', '1');
      properties.writeTo(builder);
      image.writeTo(builder);
    });
  }
}

extension GroupLayerWriter on Group {
  void writeTo(XmlBuilder builder) {
    builder.element('group', nest: () {
      _writeCommonAttributes(builder);
      properties.writeTo(builder);
      for (final subLayer in layers) {
        subLayer.writeTo(builder);
      }
    });
  }
}

extension TiledObjectWriter on TiledObject {
  void writeTo(XmlBuilder builder) {
    builder.element('object', nest: () {
      builder.attribute('id', id);
      if (name.isNotEmpty) builder.attribute('name', name);
      if (type.isNotEmpty) {
        builder.attribute('type', type); 
        builder.attribute('class', type);
      }
      if (gid != null) builder.attribute('gid', gid!);
      builder.attribute('x', x);
      builder.attribute('y', y);
      if (width != 0) builder.attribute('width', width);
      if (height != 0) builder.attribute('height', height);
      if (rotation != 0) builder.attribute('rotation', rotation);
      if (!visible) builder.attribute('visible', '0');
      // --- FIX 2: Check for template existence, not `isNotEmpty`. ---
      if (template != null) builder.attribute('template', template!);

      properties.writeTo(builder);

      if (isEllipse) builder.element('ellipse');
      else if (isPoint) builder.element('point');
      else if (isPolygon) {
        builder.element('polygon', nest: () => builder.attribute('points', polygon.map((p) => '${p.x},${p.y}').join(' ')));
      } else if (isPolyline) {
        builder.element('polyline', nest: () => builder.attribute('points', polyline.map((p) => '${p.x},${p.y}').join(' ')));
      }

      text?.writeTo(builder);
    });
  }
}

extension TextWriter on Text {
  void writeTo(XmlBuilder builder) {
    builder.element('text', nest: () {
      if (fontFamily != 'sans-serif') builder.attribute('fontfamily', fontFamily);
      if (pixelSize != 16) builder.attribute('pixelsize', pixelSize);
      if (wrap) builder.attribute('wrap', '1');
      if (color != '#000000') builder.attribute('color', color);
      if (bold) builder.attribute('bold', '1');
      if (italic) builder.attribute('italic', '1');
      if (underline) builder.attribute('underline', '1');
      if (strikeout) builder.attribute('strikeout', '1');
      if (!kerning) builder.attribute('kerning', '0');
      if (hAlign != HAlign.left) builder.attribute('halign', hAlign.name);
      if (vAlign != VAlign.top) builder.attribute('valign', vAlign.name);
      builder.text(text);
    });
  }
}

extension PropertiesWriter on CustomProperties {
  void writeTo(XmlBuilder builder) {
    if (isEmpty) return;
    builder.element('properties', nest: () {
      // --- FIX 3: Iterate over the CustomProperties object directly. ---
      for (final property in this) {
        property.writeTo(builder);
      }
    });
  }
}

extension PropertyWriter on Property {
  void writeTo(XmlBuilder builder) {
    builder.element('property', nest: () {
      builder.attribute('name', name);
      
      switch (runtimeType) {
        case IntProperty: builder.attribute('type', 'int'); break;
        case BoolProperty: builder.attribute('type', 'bool'); break;
        case FloatProperty: builder.attribute('type', 'float'); break;
        case FileProperty: builder.attribute('type', 'file'); break;
        case ObjectProperty: builder.attribute('type', 'object'); break;
        case ColorProperty:
          builder.attribute('type', 'color');
          builder.attribute('value', (this as ColorProperty).value.toHex(includeAlpha: true));
          return;
      }
      
      if (this is StringProperty && (value as String).contains('\n')) {
          builder.text(value);
      } else {
          builder.attribute('value', value.toString());
      }
    });
  }
}