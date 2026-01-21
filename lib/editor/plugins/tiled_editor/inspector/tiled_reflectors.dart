import 'package:tiled/tiled.dart';
import 'property_descriptors.dart';
import '../models/object_class_model.dart';
import '../tiled_asset_resolver.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:flutter/material.dart' hide StringProperty;

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
extension on Color {
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
  static List<PropertyDescriptor> getDescriptors(
    Object? obj, {
    Map<String, ObjectClassDefinition>? schema,
    TiledAssetResolver? resolver,
  }) {
    if (obj == null) return [];
    
    if (obj is TiledObject) {
      return _getTiledObjectDescriptors(obj, schema, resolver);
    }
    // ... Pass through for other types (Map, Layer, etc)
    if (obj is TiledMap) return (obj as TiledMap).getDescriptors();
    if (obj is Layer) return (obj as Layer).getDescriptors(); 
    if (obj is Tileset) return (obj as Tileset).getDescriptors();
    
    return [];
  }

  static List<PropertyDescriptor> _getTiledObjectDescriptors(
    TiledObject obj, 
    Map<String, ObjectClassDefinition>? schema,
    TiledAssetResolver? resolver,
  ) {
    final descriptors = <PropertyDescriptor>[
      IntPropertyDescriptor(name: 'id', label: 'ID', getter: () => obj.id, setter: (v) {}, isReadOnly: true),
      StringPropertyDescriptor(name: 'name', label: 'Name', getter: () => obj.name, setter: (v) => obj.name = v),
      
      // Class Selector
      StringEnumPropertyDescriptor(
        name: 'type', 
        label: 'Class', 
        getter: () => obj.type.isEmpty ? 'None' : obj.type,
        setter: (v) {
          final newType = (v == 'None' ? '' : v);
          final oldType = obj.type;

          // Only perform logic if type actually changed and schema is available
          if (schema != null && newType != oldType) {
            final oldDef = schema[oldType];
            final newDef = schema[newType];
            
            // Check current 'displayColor' property (raw)
            final currentProp = obj.properties['displayColor'];
            final currentHex = (currentProp is StringProperty) ? currentProp.value : null;

            bool shouldUpdateColor = false;

            if (currentHex == null || currentHex.isEmpty) {
              // No explicit color set, always adopt the new class default
              shouldUpdateColor = true;
            } else if (oldDef != null) {
              // Explicit color exists. Check if it matches the OLD class default.
              final oldDefaultHex = oldDef.color.toHex(includeAlpha: true);
              
              // If current color is the same as the old default, it means the user 
              // likely didn't customize it (or reset it). We should switch to the new default.
              if (currentHex.trim().toLowerCase() == oldDefaultHex.toLowerCase()) {
                shouldUpdateColor = true;
              }
              // Else: It's a custom color, preserve it.
            } else {
              // Old type didn't exist in schema (or was None), but we have a color.
              // Treat as custom color. Do not update.
              shouldUpdateColor = false;
            }

            // Apply new default color if conditions met
            if (shouldUpdateColor && newDef != null) {
              obj.properties.byName['displayColor'] = Property(
                name: 'displayColor',
                type: PropertyType.color,
                value: newDef.color.toHex(includeAlpha: true),
              );
            }
          }

          obj.type = newType;
        },
        options: [
          'None',
          if (schema != null) ...schema.keys
        ],
      ),
      
      // Display Color Override
      ColorPropertyDescriptor(
        name: 'displayColor', 
        label: 'Display Color', 
        getter: () {
          final prop = obj.properties['displayColor'];
          if (prop is StringProperty) return prop.value;
          
          // If no override is set, show the Schema Default for clarity in UI
          if (schema != null && schema.containsKey(obj.type)) {
            return schema[obj.type]!.color.toHex(includeAlpha: true);
          }
          
          return null; // Will show as "Not set" / transparent
        }, 
        setter: (v) {
          if (v.isEmpty) {
            obj.properties.byName.remove('displayColor');
          } else {
            obj.properties.byName['displayColor'] = Property(
              name: 'displayColor', 
              type: PropertyType.color, 
              value: v
            );
          }
        }
      ),

      DoublePropertyDescriptor(name: 'x', label: 'X', getter: () => obj.x, setter: (v) => obj.x = v),
      DoublePropertyDescriptor(name: 'y', label: 'Y', getter: () => obj.y, setter: (v) => obj.y = v),
      DoublePropertyDescriptor(name: 'width', label: 'Width', getter: () => obj.width, setter: (v) => obj.width = v),
      DoublePropertyDescriptor(name: 'height', label: 'Height', getter: () => obj.height, setter: (v) => obj.height = v),
      DoublePropertyDescriptor(name: 'rotation', label: 'Rotation', getter: () => obj.rotation, setter: (v) => obj.rotation = v),

      // --- RESTORED: Flow Graph Property ---
      FlowGraphReferencePropertyDescriptor(
        name: 'flowGraph',
        label: 'Flow Graph (.fg)',
        getter: () {
          final prop = obj.properties['flowGraph'];
          return (prop is StringProperty) ? prop.value : '';
        },
        setter: (val) {
          if (val.isEmpty) {
            obj.properties.byName.remove('flowGraph');
          } else {
            obj.properties.byName['flowGraph'] = StringProperty(name: 'flowGraph', value: val);
          }
        },
      ),
    ];

    // Restore Read-Only properties for specific shapes/text
    if (obj.isPolygon) {
      descriptors.add(StringPropertyDescriptor(name: 'polygon', label: 'Polygon Points', getter: () => obj.polygon.map((p) => '${p.x},${p.y}').join(' '), setter: (v) {}, isReadOnly: true));
    }
    if (obj.isPolyline) {
      descriptors.add(StringPropertyDescriptor(name: 'polyline', label: 'Polyline Points', getter: () => obj.polyline.map((p) => '${p.x},${p.y}').join(' '), setter: (v) {}, isReadOnly: true));
    }
    if (obj.text != null) {
      // Basic text preview if needed, or expand for full text editing later
      descriptors.add(StringPropertyDescriptor(name: 'text_content', label: 'Text Content', getter: () => obj.text!.text, setter: (v) => obj.text!.text = v));
    }

    // 3. Schema Member Generation
    final currentClass = obj.type;
    if (schema != null && schema.containsKey(currentClass)) {
      final definition = schema[currentClass]!;
      for (final member in definition.members) {
        descriptors.add(_createMemberDescriptor(obj, member, resolver));
      }
    }

    // 4. Custom Properties
    descriptors.add(CustomPropertiesDescriptor(
      name: 'properties', 
      label: 'Raw Properties', 
      getter: () => obj.properties, 
      setter: (v) => obj.properties = v
    ));

    return descriptors;
  }

  static PropertyDescriptor _createMemberDescriptor(
    TiledObject obj, 
    ClassMemberDefinition member,
    TiledAssetResolver? resolver,
  ) {
    dynamic getValue() {
      final prop = obj.properties[member.name];
      if (prop != null) return prop.value;
      return member.defaultValue;
    }

    void setValue(dynamic val, PropertyType type) {
      obj.properties.byName[member.name] = Property(
        name: member.name, 
        type: type, 
        value: val
      );
    }

    // Special Case: Atlas Sprite Animation Selector
    if ((member.name == 'initialAnim' || member.name == 'initialFrame') && resolver != null) {
      return DynamicEnumPropertyDescriptor(
        name: member.name,
        label: member.name,
        getter: () => getValue().toString(),
        setter: (v) => setValue(v, PropertyType.string),
        fetchOptions: () {
          // 1. Find the sibling 'atlas' property
          final atlasProp = obj.properties['atlas'];
          if (atlasProp is! StringProperty) return [];
          
          final atlasPath = atlasProp.value;
          if (atlasPath.isEmpty) return [];

          // 2. Resolve relative to TMX file
          final canonicalKey = resolver.repo.resolveRelativePath(resolver.tmxPath, atlasPath);
          
          // 3. Load the Asset
          final asset = resolver.getAsset(canonicalKey);

          // 4. Return options based on .tpacker data
          if (asset is TexturePackerAssetData) {
            final options = <String>[];
            if (member.name == 'initialAnim') {
               options.addAll(asset.animations.keys);
            } else {
               options.addAll(asset.frames.keys);
            }
            return options;
          }
          return [];
        },
      );
    }

    // Standard Schema Types
    switch (member.type) {
      case ClassMemberType.string:
        return StringPropertyDescriptor(
          name: member.name,
          label: member.name,
          getter: () => getValue().toString(),
          setter: (v) => setValue(v, PropertyType.string),
        );
      case ClassMemberType.int:
        return IntPropertyDescriptor(
          name: member.name,
          label: member.name,
          getter: () => (getValue() as num?)?.toInt() ?? 0,
          setter: (v) => setValue(v, PropertyType.int),
        );
      case ClassMemberType.float:
        return DoublePropertyDescriptor(
          name: member.name,
          label: member.name,
          getter: () => (getValue() as num?)?.toDouble() ?? 0.0,
          setter: (v) => setValue(v, PropertyType.float),
        );
      case ClassMemberType.bool:
        return BoolPropertyDescriptor(
          name: member.name,
          label: member.name,
          getter: () => getValue() == true,
          setter: (v) => setValue(v, PropertyType.bool),
        );
      case ClassMemberType.color:
        return ColorPropertyDescriptor(
          name: member.name,
          label: member.name,
          getter: () {
            final val = getValue();
            if (val is String) return val;
            return '#FFFFFFFF'; 
          },
          setter: (v) => setValue(v, PropertyType.color),
        );
      case ClassMemberType.file:
        return SchemaFilePropertyDescriptor(
          name: member.name,
          label: member.name,
          getter: () => getValue().toString(),
          setter: (v) => setValue(v, PropertyType.file),
        );
      case ClassMemberType.enum_:
        return StringEnumPropertyDescriptor(
          name: member.name,
          label: member.name,
          getter: () => getValue().toString(),
          setter: (v) => setValue(v, PropertyType.string),
          options: member.options ?? [],
        );
    }
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
      FlowGraphReferencePropertyDescriptor(
        name: 'flowGraph',
        label: 'Flow Graph (.fg)',
        getter: () {
          final prop = properties['flowGraph'];
          return (prop is StringProperty) ? prop.value : '';
        },
        setter: (val) {
          if (val.isEmpty) {
            properties.byName.remove('flowGraph');
          } else {
            properties.byName['flowGraph'] = StringProperty(name: 'flowGraph', value: val);
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

// Helper class because EnumPropertyDescriptor expects an Enum
