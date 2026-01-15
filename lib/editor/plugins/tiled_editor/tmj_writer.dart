import 'dart:convert';
import 'package:tiled/tiled.dart';

// Helper extensions to convert Tiled enums and objects to JSON-compatible strings
extension _EnumWriter on Enum {
  String toJson() => name;
}

extension _ColorDataWriter on ColorData {
  String toJson() {
    final r = red.toRadixString(16).padLeft(2, '0');
    final g = green.toRadixString(16).padLeft(2, '0');
    final b = blue.toRadixString(16).padLeft(2, '0');
    final a = alpha.toRadixString(16).padLeft(2, '0');
    return '#$a$r$g$b';
  }
}

class TmjWriter {
  final TiledMap map;

  TmjWriter(this.map);

  String toTmj() {
    final mapJson = _buildMapJson();
    return const JsonEncoder.withIndent('  ').convert(mapJson);
  }

  Map<String, dynamic> _buildMapJson() {
    return {
      'type': 'map',
      'version': map.version,
      if (map.tiledVersion != null) 'tiledversion': map.tiledVersion,
      'orientation': map.orientation?.toJson() ?? 'orthogonal',
      'renderorder': map.renderOrder.toJson().replaceAllMapped(RegExp(r'([A-Z])'), (m) => '-${m.group(1)!.toLowerCase()}'),
      'width': map.width,
      'height': map.height,
      'tilewidth': map.tileWidth,
      'tileheight': map.tileHeight,
      'infinite': map.infinite,
      if (map.nextLayerId != null) 'nextlayerid': map.nextLayerId,
      if (map.nextObjectId != null) 'nextobjectid': map.nextObjectId,
      if (map.backgroundColorHex != null) 'backgroundcolor': map.backgroundColorHex,
      if (map.properties.isNotEmpty) 'properties': _buildPropertiesJson(map.properties),
      'tilesets': map.tilesets.map((ts) => _buildTilesetJson(ts)).toList(),
      'layers': map.layers.map((l) => _buildLayerJson(l)).toList(),
    };
  }

  List<Map<String, dynamic>> _buildPropertiesJson(CustomProperties properties) {
    return properties.map((prop) {
      final json = <String, dynamic>{
        'name': prop.name,
        'type': prop.type.name,
        'value': prop.value,
      };
      // The tiled package stores ColorProperty's value as ColorData object.
      // The JSON format expects the hex string for the value.
      if (prop is ColorProperty) {
        json['value'] = prop.hexValue;
      }
      return json;
    }).toList();
  }

  Map<String, dynamic> _buildTilesetJson(Tileset tileset) {
    final json = <String, dynamic>{
      'firstgid': tileset.firstGid,
      if (tileset.source != null) 'source': tileset.source,
    };

    if (tileset.source == null) {
      json.addAll({
        if (tileset.name != null) 'name': tileset.name,
        'tilewidth': tileset.tileWidth,
        'tileheight': tileset.tileHeight,
        if (tileset.spacing != 0) 'spacing': tileset.spacing,
        if (tileset.margin != 0) 'margin': tileset.margin,
        if (tileset.tileCount != null) 'tilecount': tileset.tileCount,
        if (tileset.columns != null) 'columns': tileset.columns,
        if (tileset.image != null) 'image': tileset.image!.source,
        if (tileset.image != null) 'imagewidth': tileset.image!.width,
        if (tileset.image != null) 'imageheight': tileset.image!.height,
        if (tileset.objectAlignment != ObjectAlignment.unspecified) 'objectalignment': tileset.objectAlignment.toJson(),
        if (tileset.properties.isNotEmpty) 'properties': _buildPropertiesJson(tileset.properties),
      });
    }

    return json;
  }

  Map<String, dynamic> _buildLayerJson(Layer layer) {
    final common = {
      'id': layer.id,
      'name': layer.name,
      'x': layer.offsetX,
      'y': layer.offsetY,
      'width': layer is TileLayer ? layer.width : 0,
      'height': layer is TileLayer ? layer.height : 0,
      'opacity': layer.opacity,
      'visible': layer.visible,
      if (layer.class_ != null && layer.class_!.isNotEmpty) 'class': layer.class_,
      if (layer.tintColorHex != null) 'tintcolor': layer.tintColorHex,
      if (layer.properties.isNotEmpty) 'properties': _buildPropertiesJson(layer.properties),
    };

    if (layer is TileLayer) {
      common['type'] = 'tilelayer';
      final gids = layer.tileData?.expand((row) => row).map((gid) {
        int outputGid = gid.tile;
        if (gid.flips.horizontally) outputGid |= Gid.flippedHorizontallyFlag;
        if (gid.flips.vertically) outputGid |= Gid.flippedVerticallyFlag;
        if (gid.flips.diagonally) outputGid |= Gid.flippedDiagonallyFlag;
        return outputGid;
      }).toList();
      common['data'] = gids ?? [];
    } else if (layer is ObjectGroup) {
      common['type'] = 'objectgroup';
      common['draworder'] = layer.drawOrder?.toJson() ?? 'topdown';
      if (layer.color != null) {
        common['color'] = layer.color!.toJson();
      }
      common['objects'] = layer.objects.map((o) => _buildObjectJson(o)).toList();
    } else if (layer is ImageLayer) {
      common['type'] = 'imagelayer';
      common['image'] = layer.image.source;
      if(layer.repeatX) common['repeatx'] = true;
      if(layer.repeatY) common['repeaty'] = true;
    } else if (layer is Group) {
      common['type'] = 'group';
      common['layers'] = layer.layers.map((l) => _buildLayerJson(l)).toList();
    }
    return common;
  }

  Map<String, dynamic> _buildObjectJson(TiledObject obj) {
    return {
      'id': obj.id,
      'name': obj.name,
      'type': obj.type, // This is the primary editable field
      if (obj.type.isNotEmpty) 'class': obj.type, // Also write to 'class' if 'type' is set
      'x': obj.x,
      'y': obj.y,
      'width': obj.width,
      'height': obj.height,
      'rotation': obj.rotation,
      'visible': obj.visible,
      if (obj.gid != null) 'gid': obj.gid,
      if (obj.isEllipse) 'ellipse': true,
      if (obj.isPoint) 'point': true,
      if (obj.isPolygon) 'polygon': obj.polygon.map((p) => {'x': p.x, 'y': p.y}).toList(),
      if (obj.isPolyline) 'polyline': obj.polyline.map((p) => {'x': p.x, 'y': p.y}).toList(),
      if (obj.properties.isNotEmpty) 'properties': _buildPropertiesJson(obj.properties),
      if (obj.text != null) 'text': _buildTextJson(obj.text!),
    };
  }

  Map<String, dynamic> _buildTextJson(Text text) {
    return {
      'text': text.text,
      'fontfamily': text.fontFamily,
      'pixelsize': text.pixelSize,
      'wrap': text.wrap,
      'color': text.color,
      'bold': text.bold,
      'italic': text.italic,
      'underline': text.underline,
      'strikeout': text.strikeout,
      'kerning': text.kerning,
      'halign': text.hAlign.toJson(),
      'valign': text.vAlign.toJson(),
    };
  }
}