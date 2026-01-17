import 'package:flutter/material.dart' hide ColorProperty;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flex_color_picker/flex_color_picker.dart'; // <-- IMPORT THE PACKAGE
import 'package:machine/asset_cache/asset_models.dart';
import 'package:path/path.dart' as p; // Add path import

import 'property_descriptors.dart';
import '../tiled_editor_widget.dart';
import '../../../../widgets/dialogs/folder_picker_dialog.dart';
import '../image_load_result.dart';
import '../../../../utils/toast.dart';
import 'package:tiled/tiled.dart' hide Text; // <--- ADD THIS IMPORT
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/asset_cache/asset_models.dart';
import '../widgets/sprite_picker_dialog.dart'; // Import the new file

class PropertyFileListEditor extends StatelessWidget {
  final FileListPropertyDescriptor descriptor;
  final VoidCallback onUpdate;
  final GlobalKey<TiledEditorWidgetState> editorKey;
  final String contextPath; // Add this field

  const PropertyFileListEditor({
    super.key,
    required this.descriptor,
    required this.onUpdate,
    required this.editorKey,
    required this.contextPath, // Add this parameter
  });

  Future<void> _addFile(BuildContext context, WidgetRef ref) async { // Added ref
    final paths = List<String>.from(descriptor.currentValue);
    final repo = ref.read(projectRepositoryProvider)!; // Access Repo
    
    // Returns a project-relative path (e.g. "assets/atlases/items.tpacker")
    final newPath = await showDialog<String>(
      context: context,
      builder: (_) => const FileOrFolderPickerDialog(),
    );
    
    if (newPath != null) {
      // REFACTORED: Use repository to calculate the relative path from the TMX to the Atlas
      final relativePath = repo.calculateRelativePath(contextPath, newPath);

      paths.add(relativePath); 
      descriptor.updateValue(paths);
      onUpdate();
    }
  }

  void _removeFile(int index) {
    final paths = List<String>.from(descriptor.currentValue);
    paths.removeAt(index);
    descriptor.updateValue(paths);
    onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final files = descriptor.currentValue;
    
    return ExpansionTile(
      title: Text(descriptor.label),
      subtitle: Text('${files.length} linked'),
      children: [
        for (int i = 0; i < files.length; i++)
          ListTile(
            title: Text(files[i]),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _removeFile(i),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Link Texture Packer File'),
          onTap: () => _addFile(context, ref), // Pass ref
        ),
      ],
    );
  }
}

class PropertySpriteSelector extends StatelessWidget {
  final SpriteReferencePropertyDescriptor descriptor;
  final VoidCallback onUpdate;
  final Map<String, AssetData> assetDataMap;

  const PropertySpriteSelector({
    super.key,
    required this.descriptor,
    required this.onUpdate,
    required this.assetDataMap,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Aggregate all available sprites from loaded TexturePacker assets
    final Map<String, TexturePackerAssetData> availableAtlases = {};
    final List<String> allSpriteNames = [];

    assetDataMap.forEach((key, value) {
      if (value is TexturePackerAssetData) {
        availableAtlases[key] = value;
        allSpriteNames.addAll(value.frames.keys);
        // We could also add animations: value.animations.keys
      }
    });
    
    allSpriteNames.sort();

    final currentVal = descriptor.currentValue;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(descriptor.label),
      subtitle: Text(currentVal.isEmpty ? 'None' : currentVal),
      trailing: const Icon(Icons.arrow_drop_down),
      onTap: () async {
        if (allSpriteNames.isEmpty) {
          MachineToast.info('No .tpacker files linked or loaded.');
          return;
        }

        // Use the shared dialog class
        final selected = await showDialog<String>(
          context: context,
          builder: (ctx) => SpritePickerDialog(spriteNames: allSpriteNames),
        );

        if (selected != null) {
          descriptor.updateValue(selected);
          onUpdate();
        }
      },
    );
  }
}

class _SpritePickerDialog extends StatefulWidget {
  final List<String> spriteNames;
  const _SpritePickerDialog({required this.spriteNames});

  @override
  State<_SpritePickerDialog> createState() => _SpritePickerDialogState();
}

class _SpritePickerDialogState extends State<_SpritePickerDialog> {
  late List<String> _filtered;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.spriteNames;
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.spriteNames;
      } else {
        _filtered = widget.spriteNames
            .where((s) => s.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Sprite'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filter,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final name = _filtered[index];
                  return ListTile(
                    title: Text(name),
                    onTap: () => Navigator.of(context).pop(name),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // Cancel
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''), // Clear selection
          child: const Text('Clear'),
        ),
      ],
    );
  }
}

class PropertyIntInput extends StatelessWidget {
  final IntPropertyDescriptor descriptor;
  final VoidCallback onUpdate;
  const PropertyIntInput({super.key, required this.descriptor, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: descriptor.currentValue.toString(),
      decoration: InputDecoration(labelText: descriptor.label),
      keyboardType: TextInputType.number,
      readOnly: descriptor.isReadOnly,
      onChanged: (value) {
        descriptor.updateValue(value);
        onUpdate();
      },
    );
  }
}

class PropertyDoubleInput extends StatelessWidget {
  final DoublePropertyDescriptor descriptor;
  final VoidCallback onUpdate;
  const PropertyDoubleInput({super.key, required this.descriptor, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: descriptor.currentValue.toString(),
      decoration: InputDecoration(labelText: descriptor.label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      readOnly: descriptor.isReadOnly,
      onChanged: (value) {
        descriptor.updateValue(value);
        onUpdate();
      },
    );
  }
}

class PropertyStringInput extends StatelessWidget {
  final StringPropertyDescriptor descriptor;
  final VoidCallback onUpdate;
  const PropertyStringInput({super.key, required this.descriptor, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: descriptor.currentValue,
      decoration: InputDecoration(labelText: descriptor.label),
      readOnly: descriptor.isReadOnly,
      onChanged: (value) {
        descriptor.updateValue(value);
        onUpdate();
      },
    );
  }
}

class PropertyBoolSwitch extends StatelessWidget {
  final BoolPropertyDescriptor descriptor;
  final VoidCallback onUpdate;
  const PropertyBoolSwitch({super.key, required this.descriptor, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(descriptor.label),
      value: descriptor.currentValue,
      onChanged: descriptor.isReadOnly ? null : (value) {
        descriptor.updateValue(value);
        onUpdate();
      },
    );
  }
}

class PropertyImagePathInput extends ConsumerWidget {
  final ImagePathPropertyDescriptor descriptor;
  final VoidCallback onUpdate;
  final AssetData? imageAsset;
  final GlobalKey<TiledEditorWidgetState> editorKey;
  final Object parentObject; // <-- CHANGED: Now required

  const PropertyImagePathInput({
    super.key,
    required this.descriptor,
    required this.onUpdate,
    required this.imageAsset,
    required this.editorKey,
    required this.parentObject,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasError = imageAsset?.hasError ?? false; 
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(descriptor.label),
      subtitle: Text(
        descriptor.currentValue,
        style: TextStyle(color: hasError ? theme.colorScheme.error : null),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(hasError ? Icons.error_outline : Icons.folder_open_outlined),
      onTap: () async {
        final newPath = await showDialog<String>(
          context: context,
          builder: (_) => const FileOrFolderPickerDialog(),
        );
        if (newPath != null && newPath != descriptor.currentValue) {
          // --- THIS IS THE FIX ---
          // The widget now has the correct parent object to pass to the reload method.
          await editorKey.currentState?.reloadImageSource(
            parentObject: parentObject,
            oldSourcePath: descriptor.currentValue,
            newProjectPath: newPath,
          );
          onUpdate();
        }
      },
    );
  }
}

class PropertyColorInput extends StatelessWidget {
  final ColorPropertyDescriptor descriptor;
  final VoidCallback onUpdate;

  const PropertyColorInput({super.key, required this.descriptor, required this.onUpdate});

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) {
      return const Color(0x00000000); // Transparent signifies "not set"
    }
    var source = hex.replaceAll('#', '');
    if (source.length == 6) {
      source = 'ff$source';
    }
    try {
      return Color(int.parse(source, radix: 16));
    } catch (e) {
      return Colors.pink; // Error color
    }
  }

  String _formatColor(Color color) {
    // Format to #AARRGGBB
    return '#${color.value.toRadixString(16).padLeft(8, '0')}';
  }

  Future<void> _showColorPickerDialog(BuildContext context) async {
    final initialColor = _parseColor(descriptor.currentValue);
    Color pickerColor = initialColor;

    final result = await showDialog<dynamic>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Color for ${descriptor.label}'),
          content: SingleChildScrollView(
            child: ColorPicker(
              color: pickerColor,
              onColorChanged: (Color color) => pickerColor = color,
              width: 40,
              height: 40,
              spacing: 5,
              runSpacing: 5,
              borderRadius: 4,
              wheelDiameter: 165,
              enableOpacity: true,
              showColorCode: true,
              colorCodeHasColor: true,
              pickersEnabled: const <ColorPickerType, bool>{
                ColorPickerType.both: false,
                ColorPickerType.primary: true,
                ColorPickerType.accent: true,
                ColorPickerType.bw: false,
                ColorPickerType.custom: true,
                ColorPickerType.wheel: true,
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Clear'),
              onPressed: () => Navigator.of(context).pop('clear'),
            ),
            // The Spacer widget is removed.
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            FilledButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(pickerColor),
            ),
          ],
        );
      },
    );

    if (result is Color) {
      descriptor.updateValue(_formatColor(result));
      onUpdate();
    } else if (result == 'clear') {
      descriptor.updateValue('');
      onUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _parseColor(descriptor.currentValue);
    final isNotSet = currentColor.alpha == 0 && descriptor.currentValue != '#00000000';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(descriptor.label),
      subtitle: isNotSet ? const Text('Not set') : null,
      trailing: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isNotSet ? Theme.of(context).scaffoldBackgroundColor : currentColor,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: isNotSet 
            ? Center(child: Icon(Icons.close, size: 20, color: Theme.of(context).disabledColor))
            : null,
      ),
      onTap: descriptor.isReadOnly ? null : () => _showColorPickerDialog(context),
    );
  }
}

class PropertyEnumDropdown<T extends Enum> extends StatelessWidget {
  final EnumPropertyDescriptor<T> descriptor;
  final VoidCallback onUpdate;

  const PropertyEnumDropdown({super.key, required this.descriptor, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      decoration: InputDecoration(labelText: descriptor.label),
      value: descriptor.currentValue,
      items: descriptor.allValues.map((T value) {
        return DropdownMenuItem<T>(
          value: value,
          child: Text(value.name),
        );
      }).toList(),
      onChanged: descriptor.isReadOnly ? null : (T? newValue) {
        if (newValue != null) {
          descriptor.updateValue(newValue);
          onUpdate();
        }
      },
    );
  }
}

class CustomPropertiesEditor extends StatefulWidget {
  final CustomPropertiesDescriptor descriptor;
  final VoidCallback onUpdate;

  const CustomPropertiesEditor({
    super.key,
    required this.descriptor,
    required this.onUpdate,
  });

  @override
  State<CustomPropertiesEditor> createState() => _CustomPropertiesEditorState();
}

class _CustomPropertiesEditorState extends State<CustomPropertiesEditor> {
  void _updateOrAddProperty(Map<String, dynamic> data) {
    final String name = data['name'];
    final PropertyType type = data['type'];
    final dynamic value = data['value'];

    Property<Object> newProperty;
    switch (type) {
      case PropertyType.bool:
        newProperty = BoolProperty(name: name, value: value as bool);
        break;
      case PropertyType.int:
        newProperty = IntProperty(name: name, value: value as int);
        break;
      case PropertyType.float:
        newProperty = FloatProperty(name: name, value: value as double);
        break;
      case PropertyType.color:
        final hexValue = value as String;
        newProperty = ColorProperty(
          name: name,
          value: colorDataFromHex(hexValue),
          hexValue: hexValue,
        );
        break;
      case PropertyType.string:
      default:
        newProperty = StringProperty(name: name, value: value as String);
        break;
    }

    final newPropertiesMap = Map<String, Property<Object>>.from(widget.descriptor.currentValue.byName);
    newPropertiesMap[name] = newProperty; // This works for both add and edit
    widget.descriptor.updateValue(CustomProperties(newPropertiesMap));
    widget.onUpdate();
  }
  
  void _addProperty() async {
    // Open the dialog in "add mode"
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AddPropertyDialog(),
    );

    if (result != null) {
      final String name = result['name'];
      // Prevent adding a property with a name that already exists
      if (widget.descriptor.currentValue.byName[name] == null) {
        _updateOrAddProperty(result);
      } else {
        MachineToast.error('A property with that name already exists.');
      }
    }
  }

  void _editProperty(Property property) async {
    // Open the dialog in "edit mode"
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AddPropertyDialog(existingProperty: property),
    );

    if (result != null) {
      // Same logic as add, but since the name is the same, it will just replace the value
      _updateOrAddProperty(result);
    }
  }

  void _removeProperty(String name) {
    final newPropertiesMap = Map<String, Property<Object>>.from(widget.descriptor.currentValue.byName);
    newPropertiesMap.remove(name);
    widget.descriptor.updateValue(CustomProperties(newPropertiesMap));
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final properties = widget.descriptor.currentValue.toList();

    return ExpansionTile(
      title: Text(widget.descriptor.label),
      initiallyExpanded: false,
      children: [
        for (final prop in properties)
          ListTile(
            title: Text(prop.name),
            subtitle: Text('${prop.value} (${prop.type.name})'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _removeProperty(prop.name),
            ),
            onTap: () => _editProperty(prop),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add Property'),
          onTap: _addProperty,
        ),
      ],
    );
  }
}

class _AddPropertyDialog extends StatefulWidget {
  final Property? existingProperty; // Add this to accept an existing property
  const _AddPropertyDialog({this.existingProperty});

  @override
  State<_AddPropertyDialog> createState() => _AddPropertyDialogState();
}

class _AddPropertyDialogState extends State<_AddPropertyDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  PropertyType _type = PropertyType.string;
  dynamic _value;
  bool get _isEditMode => widget.existingProperty != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      // If editing, pre-fill state from the existing property
      final prop = widget.existingProperty!;
      _name = prop.name;
      _type = prop.type;
      _value = prop is ColorProperty ? prop.hexValue : prop.value;
    } else {
      // If adding, use default values
      _value = _getDefaultValueForType(_type);
    }
  }

  dynamic _getDefaultValueForType(PropertyType type) {
    switch (type) {
      case PropertyType.bool:
        return false;
      case PropertyType.int:
        return 0;
      case PropertyType.float:
        return 0.0;
      case PropertyType.color:
        return '#FFFFFFFF';
      case PropertyType.string:
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Property'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: _name, // Use initialValue to support edit mode
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: !_isEditMode,
                readOnly: _isEditMode, // Name is the key, so it shouldn't be changed
                validator: (value) => value == null || value.isEmpty ? 'Name cannot be empty' : null,
                onSaved: (value) => _name = value!,
              ),
              DropdownButtonFormField<PropertyType>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: PropertyType.values
                    .where((t) => t != PropertyType.file && t != PropertyType.object)
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                // Disable type changes in edit mode to avoid complex value conversions
                onChanged: _isEditMode ? null : (value) {
                  if (value != null) {
                    setState(() {
                      _type = value;
                      _value = _getDefaultValueForType(value);
                    });
                  }
                },
              ),
              _buildValueEditor(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _formKey.currentState!.save();
              Navigator.pop(context, {'name': _name, 'type': _type, 'value': _value});
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildValueEditor() {
    switch (_type) {
      case PropertyType.bool:
        return SwitchListTile(
          title: const Text('Value'),
          value: _value as bool,
          onChanged: (val) => setState(() => _value = val),
        );
      case PropertyType.int:
        return TextFormField(
          decoration: const InputDecoration(labelText: 'Value'),
          initialValue: _value.toString(),
          keyboardType: TextInputType.number,
          onSaved: (val) => _value = int.tryParse(val ?? '0') ?? 0,
        );
      case PropertyType.float:
        return TextFormField(
          decoration: const InputDecoration(labelText: 'Value'),
          initialValue: _value.toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSaved: (val) => _value = double.tryParse(val ?? '0.0') ?? 0.0,
        );
      case PropertyType.color:
      case PropertyType.string:
        return TextFormField(
          decoration: const InputDecoration(labelText: 'Value'),
          initialValue: _value.toString(),
          onSaved: (val) => _value = val ?? '',
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

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