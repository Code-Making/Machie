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

class InspectorDialog extends ConsumerStatefulWidget {
  final Object target;
  final String title;
  final TiledMapNotifier notifier;
  final GlobalKey<TiledEditorWidgetState> editorKey;
  final String tabId; // CHANGED: Replaces resolver

  const InspectorDialog({
    super.key,
    required this.target,
    required this.title,
    required this.notifier,
    required this.editorKey,
    required this.tabId,
  });

  @override
  ConsumerState<InspectorDialog> createState() => _InspectorDialogState();
}

class _InspectorDialogState extends ConsumerState<InspectorDialog> {
  late Object _beforeState;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _beforeState = _deepCopyTarget(widget.target);
  }

  @override
  void dispose() {
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
    widget.notifier.notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Watch Schema
    final schemaAsync = ref.watch(projectSchemaProvider);
    final schema = schemaAsync.valueOrNull;

    // 2. Watch Asset Resolver (Reactive!)
    final resolverAsync = ref.watch(tiledAssetResolverProvider(widget.tabId));
    final resolver = resolverAsync.valueOrNull;

    // If resolver isn't ready, we can't properly reflect properties that depend on it
    if (resolver == null) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final descriptors = TiledReflector.getDescriptors(
      widget.target, 
      schema: schema, 
      resolver: resolver
    );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: descriptors.length,
          itemBuilder: (context, index) {
            final descriptor = descriptors[index];
            return _buildPropertyWidget(descriptor, resolver);
          },
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

  Widget _buildPropertyWidget(PropertyDescriptor descriptor, TiledAssetResolver resolver, {PropertyDescriptor? parentDescriptor}) {
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
      
      final image = resolver.getImage(rawPath, tileset: contextTileset);
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
    
    if (descriptor is FileListPropertyDescriptor) {
      return PropertyFileListEditor(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        editorKey: widget.editorKey,
        contextPath: resolver.tmxPath,
      );
    }
    if (descriptor is FlowGraphReferencePropertyDescriptor) {
      return PropertyFlowGraphSelector(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        contextPath: resolver.tmxPath,
      );
    }
    if (descriptor is SpriteReferencePropertyDescriptor) {
      // Legacy sprite picker
      return PropertySpriteSelector(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        assetDataMap: resolver.rawAssets,
      );
    }
    
    // NEW: Schema File Picker
    if (descriptor is SchemaFilePropertyDescriptor) {
      return PropertySchemaFileSelector(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        contextPath: resolver.tmxPath,
      );
    }
    
    // NEW: Dynamic Selector (for animations/frames from atlas)
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
      if (descriptor.currentValue.endsWith('.fg') || descriptor.name.contains('graph')) {
        return PropertyFileLinkWithAction(
          descriptor: descriptor,
          onUpdate: _onUpdate,
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
          children: imageDescriptors.map((childDesc) => _buildPropertyWidget(childDesc, resolver, parentDescriptor: descriptor)).toList(),
        );
      }
      return ListTile(title: Text('${descriptor.label}: Unsupported Type'));
    }

    return ListTile(title: Text('${descriptor.label}: ${descriptor.currentValue}'));
  }
}