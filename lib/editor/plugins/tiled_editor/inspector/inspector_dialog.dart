// FILE: lib/editor/plugins/tiled_editor/inspector/inspector_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart' as tiled; // Alias to avoid conflict with Flutter Text
import 'package:path/path.dart' as p;

import 'property_descriptors.dart';
import 'tiled_reflectors.dart';
import 'property_widgets.dart';
import '../tiled_editor_widget.dart';
import '../tiled_map_notifier.dart';
import 'package:machine/asset_cache/asset_models.dart';
import '../tiled_asset_resolver.dart'; // Import the new resolver
import '../providers/project_schema_provider.dart'; // Import the provider created in Phase 1
import '../../../../logs/logs_provider.dart';

class InspectorDialog extends ConsumerStatefulWidget {
  final Object target;
  final String title;
  final TiledMapNotifier notifier;
  final GlobalKey<TiledEditorWidgetState> editorKey;
  
  // Replaced assetDataMap and contextPath with resolver
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
      return; // No need to load anything
    }
    
    setState(() => _isLoadingParams = true);
    
    // Use the resolver to load and cache the data
    await widget.resolver.loadAndCacheFlowGraphParameters(flowGraphPath);
    
    if (mounted) {
      setState(() => _isLoadingParams = false);
    }
  }

  @override
  void dispose() {
    // Clear the resolver's cache for this inspection session
    widget.resolver.clearFlowGraphParameterCache();

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
         // The path has changed, so we need to reload the params
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

    // The reflector will now get the parameters from the resolver directly
    final descriptors = TiledReflector.getDescriptors(
      obj: widget.target, // Pass 'widget.target' as the named argument 'obj'
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
      
      // Determine context based on parent object (to handle external tilesets correctly)
      tiled.Tileset? contextTileset;
      Object? parentObject;

      // If we are inside an ObjectPropertyDescriptor (like 'image' on a Tileset),
      // the target of that descriptor is the parent object (the Tileset).
      if (parentDescriptor is ObjectPropertyDescriptor) {
         parentObject = parentDescriptor.target;
         if (parentObject is tiled.Tileset) {
           contextTileset = parentObject;
         }
      } else {
        // Fallback: if inspecting the Tileset directly (though usually we inspect properties of it)
        if (widget.target is tiled.Tileset) {
          contextTileset = widget.target as tiled.Tileset;
          parentObject = widget.target;
        }
      }
      
      // Use resolver to get the image for preview
      final image = widget.resolver.getImage(rawPath, tileset: contextTileset);
      final imageAsset = image != null ? ImageAssetData(image: image) : null;
      
      // Ensure we have a valid parent object for the reload callback
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
        assetDataMap: widget.resolver.rawAssets, // Pass raw assets map
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
          contextPath: widget.resolver.tmxPath, // Added contextPath
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
      // Changed from PropertyStringEnumDropdown to ComboBox
      return PropertyStringComboBox(
        descriptor: descriptor, 
        onUpdate: _onUpdate
      );
    }
        
    // Note: The "Type" dropdown created in reflector uses EnumPropertyDescriptor<StringEnumWrapper>
    // The existing PropertyEnumDropdown should handle it if the generic types align, 
    // or we cast it.
    if (descriptor is EnumPropertyDescriptor) {
       // You might need to cast to dynamic to let the generic widget handle the specific Enum type
       return PropertyEnumDropdown(descriptor: descriptor, onUpdate: _onUpdate);
    }

    return ListTile(title: Text('${descriptor.label}: ${descriptor.currentValue}'));
  }
}