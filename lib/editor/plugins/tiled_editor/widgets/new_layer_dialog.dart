// lib/editor/plugins/tiled_editor/widgets/new_layer_dialog.dart

import 'package:flutter/material.dart';
import 'package:tiled/tiled.dart' hide Text;

class NewLayerDialog extends StatefulWidget {
  const NewLayerDialog({super.key});

  @override
  State<NewLayerDialog> createState() => _NewLayerDialogState();
}

class _NewLayerDialogState extends State<NewLayerDialog> {
  late TextEditingController _nameController;
  LayerType _selectedType = LayerType.tileLayer;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _updateDefaultName();
  }
  
  void _updateDefaultName() {
      String newDefaultName = '';
      switch(_selectedType) {
        case LayerType.tileLayer:
          newDefaultName = 'New Tile Layer';
          break;
        case LayerType.objectGroup:
          newDefaultName = 'New Object Layer';
          break;
        case LayerType.imageLayer:
          newDefaultName = 'New Image Layer';
          break;
        case LayerType.group:
        default:
          newDefaultName = 'New Layer';
          break;
        // ------------------------
      }
      if (_nameController.text == 'New Tile Layer' ||
          _nameController.text == 'New Object Layer' ||
          _nameController.text == 'New Image Layer' ||
          _nameController.text == 'New Layer') {
        _nameController.text = newDefaultName;
      }
    }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Layer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Layer Name'),
            autofocus: true,
            onTap: () => _nameController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _nameController.text.length,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<LayerType>(
            decoration: const InputDecoration(labelText: 'Layer Type'),
            value: _selectedType,
            items: [
              const DropdownMenuItem(
                value: LayerType.tileLayer,
                child: Row(
                  children: [
                    Icon(Icons.grid_on, size: 20),
                    SizedBox(width: 8),
                    Text('Tile Layer'),
                  ],
                ),
              ),
              const DropdownMenuItem(
                value: LayerType.objectGroup,
                child: Row(
                  children: [
                    Icon(Icons.category_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Object Layer'),
                  ],
                ),
              ),
              const DropdownMenuItem(
                value: LayerType.imageLayer,
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Image Layer'),
                  ],
                ),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedType = value;
                  _updateDefaultName();
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final result = {
              'name': _nameController.text.trim(),
              'type': _selectedType,
            };
            Navigator.of(context).pop(result);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}