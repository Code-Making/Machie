import 'package:flutter/material.dart';

import 'package:tiled/tiled.dart' hide Text;

class MapPropertiesDialog extends StatefulWidget {
  final TiledMap map;
  const MapPropertiesDialog({super.key, required this.map});

  @override
  State<MapPropertiesDialog> createState() => _MapPropertiesDialogState();
}

class _MapPropertiesDialogState extends State<MapPropertiesDialog> {
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _tileWidthController;
  late final TextEditingController _tileHeightController;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: widget.map.width.toString());
    _heightController = TextEditingController(
      text: widget.map.height.toString(),
    );
    _tileWidthController = TextEditingController(
      text: widget.map.tileWidth.toString(),
    );
    _tileHeightController = TextEditingController(
      text: widget.map.tileHeight.toString(),
    );
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _tileWidthController.dispose();
    _tileHeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Map Properties'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _widthController,
              decoration: const InputDecoration(labelText: 'Map Width (tiles)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _heightController,
              decoration: const InputDecoration(
                labelText: 'Map Height (tiles)',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _tileWidthController,
              decoration: const InputDecoration(labelText: 'Tile Width (px)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _tileHeightController,
              decoration: const InputDecoration(labelText: 'Tile Height (px)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final result = {
              'width': int.tryParse(_widthController.text) ?? widget.map.width,
              'height':
                  int.tryParse(_heightController.text) ?? widget.map.height,
              'tileWidth':
                  int.tryParse(_tileWidthController.text) ??
                  widget.map.tileWidth,
              'tileHeight':
                  int.tryParse(_tileHeightController.text) ??
                  widget.map.tileHeight,
            };
            Navigator.of(context).pop(result);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
