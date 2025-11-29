import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart' as tiled; // Use a prefix

import 'property_descriptors.dart';
import 'tiled_reflectors.dart';
import 'property_widgets.dart';
import '../tiled_editor_widget.dart';
import '../tiled_map_notifier.dart';

class InspectorDialog extends ConsumerStatefulWidget {
  final Object target;
  final String title;
  final TiledMapNotifier notifier;
  final GlobalKey<TiledEditorWidgetState> editorKey;

  const InspectorDialog({
    super.key,
    required this.target,
    required this.title,
    required this.notifier,
    required this.editorKey,
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
    // Capture the state of the object when the dialog opens.
    _beforeState = _deepCopyTarget(widget.target);
  }

  @override
  void dispose() {
    // If changes were made, record them in the history.
    if (_hasChanges) {
      final afterState = _deepCopyTarget(widget.target);
      widget.notifier.recordPropertyChange(_beforeState, afterState);
      widget.notifier.notifyListeners();
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
    return target; // Fallback
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {
      _hasChanges = true;
    });
    // This live-updates the main editor view as properties are changed.
    widget.notifier.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    final descriptors = TiledReflector.getDescriptors(widget.target);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: descriptors.length,
          itemBuilder: (context, index) {
            final descriptor = descriptors[index];
            return _buildPropertyWidget(descriptor);
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

  Widget _buildPropertyWidget(PropertyDescriptor descriptor, {PropertyDescriptor? parentDescriptor}) {
    if (descriptor is ImagePathPropertyDescriptor) {
      final imageResult = widget.notifier.tilesetImages[descriptor.currentValue];
      final parentObject = (parentDescriptor as ObjectPropertyDescriptor).target;
      return PropertyImagePathInput(
        descriptor: descriptor,
        onUpdate: _onUpdate,
        imageLoadResult: imageResult,
        editorKey: widget.editorKey,
        parentObject: parentObject!,
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
          // Pass the current ObjectPropertyDescriptor as the parent to its children
          children: imageDescriptors.map((childDesc) => _buildPropertyWidget(childDesc, parentDescriptor: descriptor)).toList(),
        );
      }
      return ListTile(title: Text('${descriptor.label}: Unsupported Type'));
    }

    return ListTile(title: Text('${descriptor.label}: ${descriptor.currentValue}'));
  }
}