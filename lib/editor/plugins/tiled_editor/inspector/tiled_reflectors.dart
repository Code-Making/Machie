import 'package:tiled/tiled.dart';
import 'property_descriptors.dart';

// Helper to convert ColorData to and from Hex strings.
ColorData colorDataFromHex(String hex) {
  var source = hex.replaceAll('#', '');
  if (source.length == 6) {
    source = 'ff$source';
  }
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

// --- THE NEW REFLECTOR CLASS ---
class TiledReflector {
  static List<PropertyDescriptor> getDescriptors(Object? obj) {
    if (obj == null) return [];
    
    if (obj is TiledMap) return obj.getDescriptors();
    if (obj is Layer) return obj.getDescriptors(); 
    if (obj is Tileset) return obj.getDescriptors();
    if (obj is TiledObject) return obj.getDescriptors();
    if (obj is TiledImage) return obj.getDescriptors(null);

    return [];
  }
}

// --- EXTENSIONS FOR EACH TILED TYPE ---

extension TiledMapReflector on TiledMap {
  List<PropertyDescriptor> getDescriptors() {
    return [
      EnumPropertyDescriptor<RenderOrder>(name: 'renderOrder', label: 'Render Order', getter: () => renderOrder, setter: (v) => renderOrder = v, allValues: RenderOrder.values),
      IntPropertyDescriptor(name: 'width', label: 'Width (tiles)', getter: () => width, setter: (v) => width = v),
      IntPropertyDescriptor(name: 'height', label: 'Height (tiles)', getter: () => height, setter: (v) => height = v),
      IntPropertyDescriptor(name: 'tileWidth', label: 'Tile Width (px)', getter: () => tileWidth, setter: (v) => tileWidth = v),
      IntPropertyDescriptor(name: 'tileHeight', label: 'Tile Height (px)', getter: () => tileHeight, setter: (v) => tileHeight = v),
      ColorPropertyDescriptor(name: 'backgroundColor', label: 'Background Color', getter: () => backgroundColorHex, setter: (v) => backgroundColorHex = v),
      
      // --- NEW: Texture Packer Sources ---
      FileListPropertyDescriptor(
        name: 'tp_atlases', 
        label: 'Linked Atlases (.tpacker)', 
        getter: () {
          final prop = properties['tp_atlases'];
          if (prop is StringProperty) {
            return prop.value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          }
          return [];
        }, 
        setter: (List<String> files) {
          // FIX: Access .byName to set the property
          properties.byName['tp_atlases'] = StringProperty(name: 'tp_atlases', value: files.join(','));
        }
      ),

      CustomPropertiesDescriptor(name: 'properties', label: 'Custom Properties', getter: () => properties, setter: (v) => properties = v),
    ];
  }
}

extension LayerReflector on Layer {
  List<PropertyDescriptor> getDescriptors() {
    final common = [
      IntPropertyDescriptor(name: 'id', label: 'ID', getter: () => id ?? 0, setter: (v) {}, isReadOnly: true),
      StringPropertyDescriptor(name: 'name', label: 'Name', getter: () => name, setter: (v) => name = v),
      StringPropertyDescriptor(name: 'class', label: 'Class', getter: () => class_ ?? '', setter: (v) => class_ = v),
      DoublePropertyDescriptor(name: 'offsetX', label: 'Offset X', getter: () => offsetX, setter: (v) => offsetX = v),
      DoublePropertyDescriptor(name: 'offsetY', label: 'Offset Y', getter: () => offsetY, setter: (v) => offsetY = v),
      DoublePropertyDescriptor(name: 'opacity', label: 'Opacity', getter: () => opacity, setter: (v) => opacity = v.clamp(0.0, 1.0)),
      BoolPropertyDescriptor(name: 'visible', label: 'Visible', getter: () => visible, setter: (v) => visible = v),
      ColorPropertyDescriptor(name: 'tintColor', label: 'Tint Color', getter: () => tintColorHex, setter: (v) => tintColorHex = v),
      DoublePropertyDescriptor(name: 'parallaxX', label: 'Parallax X', getter: () => parallaxX, setter: (v) => parallaxX = v),
      DoublePropertyDescriptor(name: 'parallaxY', label: 'Parallax Y', getter: () => parallaxY, setter: (v) => parallaxY = v),
    ];

    final layer = this;
    if (layer is ObjectGroup) {
      common.addAll([
        EnumPropertyDescriptor<DrawOrder>(name: 'drawOrder', label: 'Draw Order', getter: () => layer.drawOrder ?? DrawOrder.topDown, setter: (v) => layer.drawOrder = v, allValues: DrawOrder.values),
        ColorPropertyDescriptor(name: 'color', label: 'Display Color', getter: () => layer.color?.toHex(prefix: '#', includeAlpha: true), setter: (v) => layer.color = colorDataFromHex(v)),
      ]);
    } else if (layer is ImageLayer) {
      common.addAll([
        BoolPropertyDescriptor(name: 'repeatX', label: 'Repeat X', getter: () => layer.repeatX, setter: (v) => layer.repeatX = v),
        BoolPropertyDescriptor(name: 'repeatY', label: 'Repeat Y', getter: () => layer.repeatY, setter: (v) => layer.repeatY = v),
        ObjectPropertyDescriptor(name: 'image', label: 'Image', getter: () => layer.image, target: layer),
      ]);
    }
    
    common.add(CustomPropertiesDescriptor(name: 'properties', label: 'Custom Properties', getter: () => properties, setter: (v) => properties = v));
    return common;
  }
}

extension TilesetReflector on Tileset {
  List<PropertyDescriptor> getDescriptors() {
    return [
      StringPropertyDescriptor(name: 'name', label: 'Name', getter: () => name ?? '', setter: (v) => name = v),
      IntPropertyDescriptor(name: 'tileWidth', label: 'Tile Width', getter: () => tileWidth ?? 0, setter: (v) => tileWidth = v),
      IntPropertyDescriptor(name: 'tileHeight', label: 'Tile Height', getter: () => tileHeight ?? 0, setter: (v) => tileHeight = v),
      IntPropertyDescriptor(name: 'spacing', label: 'Spacing', getter: () => spacing, setter: (v) => spacing = v),
      IntPropertyDescriptor(name: 'margin', label: 'Margin', getter: () => margin, setter: (v) => margin = v),
      EnumPropertyDescriptor<ObjectAlignment>(name: 'objectAlignment', label: 'Object Alignment', getter: () => objectAlignment, setter: (v) => objectAlignment = v, allValues: ObjectAlignment.values),
      ObjectPropertyDescriptor(name: 'image', label: 'Image', getter: () => image, target: this),
      CustomPropertiesDescriptor(name: 'properties', label: 'Custom Properties', getter: () => properties, setter: (v) => properties = v),
    ];
  }
}

extension TiledObjectReflector on TiledObject {
  List<PropertyDescriptor> getDescriptors() {
    final descriptors = <PropertyDescriptor>[
      IntPropertyDescriptor(name: 'id', label: 'ID', getter: () => id, setter: (v) {}, isReadOnly: true),
      StringPropertyDescriptor(name: 'name', label: 'Name', getter: () => name, setter: (v) => name = v),
      StringPropertyDescriptor(name: 'type', label: 'Type', getter: () => type, setter: (v) => type = v),
      StringPropertyDescriptor(name: 'class', label: 'Class', getter: () => class_, setter: (v) {}, isReadOnly: true),
      BoolPropertyDescriptor(name: 'visible', label: 'Visible', getter: () => visible, setter: (v) => visible = v),
      DoublePropertyDescriptor(name: 'x', label: 'X', getter: () => x, setter: (v) => x = v),
      DoublePropertyDescriptor(name: 'y', label: 'Y', getter: () => y, setter: (v) => y = v),
      DoublePropertyDescriptor(name: 'width', label: 'Width', getter: () => width, setter: (v) => width = v),
      DoublePropertyDescriptor(name: 'height', label: 'Height', getter: () => height, setter: (v) => height = v),
      DoublePropertyDescriptor(name: 'rotation', label: 'Rotation', getter: () => rotation, setter: (v) => rotation = v),
      IntPropertyDescriptor(name: 'gid', label: 'GID (Tile)', getter: () => gid ?? 0, setter: (v) => gid = v > 0 ? v : null),
      
      // --- NEW: Sprite Reference ---
      SpriteReferencePropertyDescriptor(
        name: 'tp_sprite',
        label: 'Texture Packer Sprite',
        getter: () {
          final prop = properties['tp_sprite'];
          return (prop is StringProperty) ? prop.value : '';
        },
        setter: (val) {
          if (val.isEmpty) {
            // FIX: Access .byName to remove the property
            properties.byName.remove('tp_sprite');
          } else {
            // FIX: Access .byName to set the property
            properties.byName['tp_sprite'] = StringProperty(name: 'tp_sprite', value: val);
          }
        },
      ),

      CustomPropertiesDescriptor(name: 'properties', label: 'Custom Properties', getter: () => properties, setter: (v) => properties = v),
    ];

    if (isPolygon) {
      descriptors.add(StringPropertyDescriptor(name: 'polygon', label: 'Polygon Points', getter: () => polygon.map((p) => '${p.x},${p.y}').join(' '), setter: (v) {}, isReadOnly: true));
    }
    if (isPolyline) {
      descriptors.add(StringPropertyDescriptor(name: 'polyline', label: 'Polyline Points', getter: () => polyline.map((p) => '${p.x},${p.y}').join(' '), setter: (v) {}, isReadOnly: true));
    }

    if (text != null) {
      final txt = text!;
      descriptors.addAll([
        StringPropertyDescriptor(name: 'text_content', label: 'Text Content', getter: () => txt.text, setter: (v) => txt.text = v),
        StringPropertyDescriptor(name: 'fontfamily', label: 'Font Family', getter: () => txt.fontFamily, setter: (v) => txt.fontFamily = v),
        IntPropertyDescriptor(name: 'pixelsize', label: 'Pixel Size', getter: () => txt.pixelSize, setter: (v) => txt.pixelSize = v),
        ColorPropertyDescriptor(name: 'color', label: 'Text Color', getter: () => txt.color, setter: (v) => txt.color = v),
        BoolPropertyDescriptor(name: 'wrap', label: 'Word Wrap', getter: () => txt.wrap, setter: (v) => txt.wrap = v),
        BoolPropertyDescriptor(name: 'bold', label: 'Bold', getter: () => txt.bold, setter: (v) => txt.bold = v),
        BoolPropertyDescriptor(name: 'italic', label: 'Italic', getter: () => txt.italic, setter: (v) => txt.italic = v),
        BoolPropertyDescriptor(name: 'underline', label: 'Underline', getter: () => txt.underline, setter: (v) => txt.underline = v),
        BoolPropertyDescriptor(name: 'strikeout', label: 'Strikeout', getter: () => txt.strikeout, setter: (v) => txt.strikeout = v),
        BoolPropertyDescriptor(name: 'kerning', label: 'Kerning', getter: () => txt.kerning, setter: (v) => txt.kerning = v),
        EnumPropertyDescriptor<HAlign>(name: 'halign', label: 'Horizontal Align', getter: () => txt.hAlign, setter: (v) => txt.hAlign = v, allValues: HAlign.values),
        EnumPropertyDescriptor<VAlign>(name: 'valign', label: 'Vertical Align', getter: () => txt.vAlign, setter: (v) => txt.vAlign = v, allValues: VAlign.values),
      ]);
    }
    
    return descriptors;
  }
}

extension TiledImageReflector on TiledImage {
  List<PropertyDescriptor> getDescriptors(Object? parent) {
     return [
      ImagePathPropertyDescriptor(
        name: 'source',
        label: 'Source',
        getter: () => source ?? '',
        setter: (v) {},
      ),
      IntPropertyDescriptor(name: 'width', label: 'Width', getter: () => width ?? 0, setter: (v) {}, isReadOnly: true),
      IntPropertyDescriptor(name: 'height', label: 'Height', getter: () => height ?? 0, setter: (v) {}, isReadOnly: true),
    ];
  }
}