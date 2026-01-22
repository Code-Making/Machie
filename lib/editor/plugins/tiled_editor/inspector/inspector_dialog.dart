// FILE: lib/editor/plugins/tiled_editor/inspector/inspector_dialog.dart

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
    widget.resolver.clearExternalMapCache();

    if (_hasChanges) {
      final afterState = _deepCopyTarget(widget.target);
      widget.notifier.recordPropertyChange(_beforeState, afterState);
      widget.notifier.notifyChange();
    }
    super.dispose();
  }
  Object _deepCopyTarget(Object target) {
    if (target is tiled.TiledObject) {
      return deepCopyTiledObject(target);
    }
    if (target is tiled.Layer) {
      return deepCopyLayer(target);
    }
    if (target is tiled.TiledMap) {
      final newMap = tiled.TiledMap(
        width: target.width,
        height: target.height,
        tileWidth: target.tileWidth,
        tileHeight: target.tileHeight,
      )
        ..backgroundColorHex = target.backgroundColorHex
        ..renderOrder = target.renderOrder;
      return newMap;
    }
    if (target is tiled.Tileset) {
      return deepCopyTileset(target);
    }
    return target;
  }

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

    // --- MODIFICATION: Pass the TiledMap to the reflector ---
    final descriptors = TiledReflector.getDescriptors(
      obj: widget.target,
      map: widget.notifier.map,
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
    if (descriptor is ExternalObjectReferencePropertyDescriptor) {
      return PropertyExternalObjectSelector(descriptor: descriptor, onUpdate: _onUpdate);
    }
    if (descriptor is TiledObjectReferencePropertyDescriptor) {
      return PropertyTiledObjectSelector(descriptor: descriptor, onUpdate: _onUpdate);
    }
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