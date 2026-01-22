import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart' as tiled;
import 'package:path/path.dart' as p;

import 'property_descriptors.dart';
import 'tiled_reflectors.dart';
import 'property_widgets.dart';
import '../tiled_editor_widget.dart';
import '../tiled_map_notifier.dart';
import 'package:machine/asset_cache/asset_models.dart';
import '../tiled_asset_resolver.dart';
import '../providers/project_schema_provider.dart';
import '../../../../logs/logs_provider.dart';

class InspectorDialog extends ConsumerStatefulWidget {
  final Object target;
  final String title;
  final TiledMapNotifier notifier;
  final GlobalKey<TiledEditorWidgetState> editorKey;
  
  final TiledAssetResolver resolver;

  const InspectorDialog({
    super.key,
    required this.target,
    required this.title,
    required this.notifier,
    required this.editorKey,
    required this.resolver,
  });

  @override
  ConsumerState<InspectorDialog> createState() => _InspectorDialogState();
}

class _InspectorDialogState extends ConsumerState<InspectorDialog> {
  late Object _beforeState;
  bool _hasChanges = false;
  
  bool _isLoadingParams = false;
  String? _currentFlowGraphPath;

  @override
  void initState() {
    super.initState();
    _beforeState = _deepCopyTarget(widget.target);
    _loadFlowGraphParametersIfNeeded();
  }

  Future<void> _loadFlowGraphParametersIfNeeded() async {
    if (widget.target is! tiled.TiledObject) return;

    final object = widget.target as tiled.TiledObject;
    final flowGraphPath = object.properties.getValue<String>('flowGraph');

    _currentFlowGraphPath = flowGraphPath;

    if (flowGraphPath == null || flowGraphPath.isEmpty) {
      return; 
    }
    
    setState(() => _isLoadingParams = true);
    
    await widget.resolver.loadAndCacheFlowGraphParameters(flowGraphPath);
    
    if (mounted) {
      setState(() => _isLoadingParams = false);
    }
  }

  @override
  void dispose() {
    widget.resolver.clearFlowGraphParameterCache();

    if (_hasChanges) {
      final afterState = _deepCopyTarget(widget.target);
      widget.notifier.recordPropertyChange(_beforeState, afterState);
      widget.notifier.notifyChange();
    }
    super.dispose();
  }

  // === FIX START ===
  Object _deepCopyTarget(Object target) {
    if (target is tiled.TiledObject) {
      return deepCopyTiledObject(obj: target);
    }
    if (target is tiled.Layer) {
      return deepCopyLayer(layer: target);
    }
    if (target is tiled.TiledMap) {
      final newMap = tiled.TiledMap(
        width: target.width,
        height: target.height,
        tileWidth: target.tileWidth,
        tileHeight: target.tileHeight,
      )
        ..backgroundColorHex = target.backgroundColorHex
        ..renderOrder = target.renderOrder
        ..properties = CustomProperties(Map.from(target.properties.byName));
      return newMap;
    }
    if (target is tiled.Tileset) {
      return deepCopyTileset(tileset: target);
    }
    return target;
  }
  // === FIX END ===

  void _onUpdate() {
    if (!mounted) return;
    setState(() {
      _hasChanges = true;
    });

    if (widget.target is tiled.TiledObject) {
       final newPath = (widget.target as tiled.TiledObject).properties.getValue<String>('flowGraph');
       if (newPath != _currentFlowGraphPath) {
         _loadFlowGraphParametersIfNeeded();
       }
    }
    widget.notifier.notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    final schemaAsync = ref.watch(projectSchemaProvider);
    final schema = schemaAsync.valueOrNull;
    final talker = ref.watch(talkerProvider);

    final descriptors = TiledReflector.getDescriptors(
      obj: widget.target, 
      schema: schema, 
      resolver: widget.resolver,
      talker: talker,
    );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (_isLoadingParams)
              const Center(child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              )),
            ...descriptors.map((descriptor) => _buildPropertyWidget(descriptor)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildPropertyWidget(PropertyDescriptor descriptor, {PropertyDescriptor? parentDescriptor}) {
    if (descriptor is ImagePathPropertyDescriptor) {
      
      final rawPath = descriptor.currentValue;
      
      tiled.Tileset? contextTileset;
      Object? parentObject;

      if (parentDescriptor is ObjectPropertyDescriptor) {
         parentObject = parentDescriptor.target;
         if (parentObject is tiled.Tileset) {
           contextTileset = parentObject;
         }
      } else {
        if (widget.target is tiled.Tileset) {
          contextTileset = widget.target as tiled.Tileset;
          parentObject = widget.target;
        }
      }
      
      final image = widget.resolver.getImage(rawPath, tileset: contextTileset);
      final imageAsset = image != null ? ImageAssetData(image: image) : null;
      
      final actualParentObject = parentObject ?? widget.target;
      
      return PropertyImagePathInput(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        imageAsset: imageAsset,
        editorKey: widget.editorKey,
        parentObject: actualParentObject,
      );
    }
    if (descriptor is SchemaFilePropertyDescriptor) {
      return PropertySchemaFileSelector(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        contextPath: widget.resolver.tmxPath,
      );
    }
    if (descriptor is FileListPropertyDescriptor) {
      return PropertyFileListEditor(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        editorKey: widget.editorKey,
        contextPath: widget.resolver.tmxPath,
      );
    }
    if (descriptor is FlowGraphReferencePropertyDescriptor) {
      return PropertyFlowGraphSelector(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        contextPath: widget.resolver.tmxPath,
      );
    }
    if (descriptor is SpriteReferencePropertyDescriptor) {
      return PropertySpriteSelector(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        assetDataMap: widget.resolver.rawAssets,
      );
    }
    if (descriptor is BoolPropertyDescriptor) {
      return PropertyBoolSwitch(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is ColorPropertyDescriptor) {
      return PropertyColorInput(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is IntPropertyDescriptor) {
      return PropertyIntInput(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is DoublePropertyDescriptor) {
      return PropertyDoubleInput(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is StringPropertyDescriptor) {
      // Check for file link convention (e.g. ends with .fg or specific property name)
      if (descriptor.currentValue.endsWith('.fg') || descriptor.name.contains('graph')) {
        return PropertyFileLinkWithAction(
          descriptor: descriptor,
          onUpdate: _onUpdate,
          contextPath: widget.resolver.tmxPath,
        );
      }
      return PropertyStringInput(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is EnumPropertyDescriptor<tiled.RenderOrder>) {
      return PropertyEnumDropdown<tiled.RenderOrder>(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is EnumPropertyDescriptor<tiled.DrawOrder>) {
      return PropertyEnumDropdown<tiled.DrawOrder>(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is EnumPropertyDescriptor<tiled.ObjectAlignment>) {
      return PropertyEnumDropdown<tiled.ObjectAlignment>(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is EnumPropertyDescriptor<tiled.HAlign>) {
      return PropertyEnumDropdown<tiled.HAlign>(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is EnumPropertyDescriptor<tiled.VAlign>) {
      return PropertyEnumDropdown<tiled.VAlign>(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is CustomPropertiesDescriptor) {
      return CustomPropertiesEditor(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is ObjectPropertyDescriptor) {
      final nestedObject = descriptor.currentValue;
      if (nestedObject == null) return const SizedBox.shrink();

      if (nestedObject is tiled.TiledImage) {
        final imageDescriptors = nestedObject.getDescriptors(descriptor.target!);
        return ExpansionTile(
          title: Text(descriptor.label),
          children: imageDescriptors.map((childDesc) => _buildPropertyWidget(childDesc, parentDescriptor: descriptor)).toList(),
        );
      }
      return ListTile(title: Text('${descriptor.label}: Unsupported Type'));
    }
  
    
    if (descriptor is DynamicEnumPropertyDescriptor) {
      return PropertyDynamicSelector(
        descriptor: descriptor,
        onUpdate: _onUpdate,
      );
    }
    
  if (descriptor is StringEnumPropertyDescriptor) {
      return PropertyStringComboBox(
        descriptor: descriptor, 
        onUpdate: _onUpdate
      );
    }
        
    if (descriptor is EnumPropertyDescriptor) {
       return PropertyEnumDropdown(descriptor: descriptor, onUpdate: _onUpdate);
    }

    return ListTile(title: Text('${descriptor.label}: ${descriptor.currentValue}'));
  }
}

// === DEEP COPY HELPERS (Copied from tiled_map_notifier.dart for self-containment) ===

Property<Object> deepCopyProperty(Property<dynamic> p) {
  if (p is StringProperty) return StringProperty(name: p.name, value: p.value);
  if (p is IntProperty) return IntProperty(name: p.name, value: p.value);
  if (p is FloatProperty) return FloatProperty(name: p.name, value: p.value);
  if (p is BoolProperty) return BoolProperty(name: p.name, value: p.value);
  if (p is ColorProperty) return ColorProperty(name: p.name, value: p.value, hexValue: p.hexValue);
  if (p is FileProperty) return FileProperty(name: p.name, value: p.value);
  if (p is ObjectProperty) return ObjectProperty(name: p.name, value: p.value);
  if (p.value is String) return StringProperty(name: p.name, value: p.value as String);
  if (p.value is int) return IntProperty(name: p.name, value: p.value as int);
  if (p.value is double) return FloatProperty(name: p.name, value: p.value as double);
  if (p.value is bool) return BoolProperty(name: p.name, value: p.value as bool);
  return Property(name: p.name, type: p.type, value: p.value);
}

TiledObject deepCopyTiledObject({required TiledObject obj}) {
  return TiledObject(
    id: obj.id, name: obj.name, type: obj.type, x: obj.x, y: obj.y,
    width: obj.width, height: obj.height, rotation: obj.rotation, gid: obj.gid,
    visible: obj.visible, rectangle: obj.rectangle, ellipse: obj.ellipse,
    point: obj.point,
    polygon: List<Point>.from(obj.polygon.map((p) => Point(x: p.x, y: p.y))),
    polyline: List<Point>.from(obj.polyline.map((p) => Point(x: p.x, y: p.y))),
    text: obj.text != null ? Text(
            text: obj.text!.text, fontFamily: obj.text!.fontFamily,
            pixelSize: obj.text!.pixelSize, wrap: obj.text!.wrap, color: obj.text!.color,
            bold: obj.text!.bold, italic: obj.text!.italic, underline: obj.text!.underline,
            strikeout: obj.text!.strikeout, kerning: obj.text!.kerning,
            hAlign: obj.text!.hAlign, vAlign: obj.text!.vAlign) : null,
    properties: CustomProperties({for (var p in obj.properties) p.name: deepCopyProperty(p)}),
  );
}

Layer deepCopyLayer({required Layer layer}) {
  if (layer is TileLayer) {
    return TileLayer(
      id: layer.id, name: layer.name, width: layer.width, height: layer.height,
      class_: layer.class_, x: layer.x, y: layer.y, offsetX: layer.offsetX, offsetY: layer.offsetY,
      parallaxX: layer.parallaxX, parallaxY: layer.parallaxY, startX: layer.startX, startY: layer.startY,
      tintColorHex: layer.tintColorHex, tintColor: layer.tintColor, opacity: layer.opacity,
      visible: layer.visible,
      properties: CustomProperties({for (var p in layer.properties) p.name: deepCopyProperty(p)}),
      compression: layer.compression, encoding: layer.encoding, chunks: layer.chunks,
    )..tileData = layer.tileData?.map((row) => List<Gid>.from(row)).toList();
  }
  if (layer is ObjectGroup) {
    return ObjectGroup(
      id: layer.id, name: layer.name, objects: layer.objects.map((o) => deepCopyTiledObject(obj: o)).toList(),
      drawOrder: layer.drawOrder, color: layer.color, class_: layer.class_,
      x: layer.x, y: layer.y, offsetX: layer.offsetX, offsetY: layer.offsetY,
      parallaxX: layer.parallaxX, parallaxY: layer.parallaxY, startX: layer.startX,
      startY: layer.startY, tintColorHex: layer.tintColorHex, tintColor: layer.tintColor,
      opacity: layer.opacity, visible: layer.visible,
      properties: CustomProperties({for (var p in layer.properties) p.name: deepCopyProperty(p)}),
      colorHex: layer.colorHex,
    );
  }
  if (layer is ImageLayer) {
    return ImageLayer(
      id: layer.id, name: layer.name, image: layer.image, repeatX: layer.repeatX, repeatY: layer.repeatY,
      class_: layer.class_, x: layer.x, y: layer.y, offsetX: layer.offsetX, offsetY: layer.offsetY,
      parallaxX: layer.parallaxX, parallaxY: layer.parallaxY, startX: layer.startX,
      startY: layer.startY, tintColorHex: layer.tintColorHex, tintColor: layer.tintColor,
      opacity: layer.opacity, visible: layer.visible,
      properties: CustomProperties({for (var p in layer.properties) p.name: deepCopyProperty(p)}),
      transparentColorHex: layer.transparentColorHex, transparentColor: layer.transparentColor,
    );
  }
  return layer;
}

Tileset deepCopyTileset({required Tileset tileset}) {
  return Tileset(
    name: tileset.name, firstGid: tileset.firstGid, tileWidth: tileset.tileWidth,
    tileHeight: tileset.tileHeight, spacing: tileset.spacing, margin: tileset.margin,
    tileCount: tileset.tileCount, columns: tileset.columns, objectAlignment: tileset.objectAlignment,
    image: tileset.image != null ? TiledImage(
            source: tileset.image!.source, width: tileset.image!.width,
            height: tileset.image!.height) : null,
    tiles: tileset.tiles.map((t) => Tile(localId: t.localId)).toList(),
     properties: CustomProperties(Map.from(tileset.properties.byName)),
  );
}