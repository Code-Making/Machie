import 'package:flutter/material.dart';

import 'package:path/path.dart' as p;

class NewTilesetDialog extends StatefulWidget {
  final String imagePath;
  const NewTilesetDialog({super.key, required this.imagePath});

  @override
  State<NewTilesetDialog> createState() => _NewTilesetDialogState();
}

class _NewTilesetDialogState extends State<NewTilesetDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _tileWidthController;
  late final TextEditingController _tileHeightController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: p.basenameWithoutExtension(widget.imagePath),
    );
    _tileWidthController = TextEditingController();
    _tileHeightController = TextEditingController();

    _tryParseDimensionsFromName();
  }

  void _tryParseDimensionsFromName() {
    final filename = p.basenameWithoutExtension(widget.imagePath).toLowerCase();
    // Regex to find patterns like 16x16, 32_32, 48-48, etc.
    final dimRegex = RegExp(r'(\d+)[x_-](\d+)');
    final match = dimRegex.firstMatch(filename);

    if (match != null) {
      final width = int.tryParse(match.group(1) ?? '');
      final height = int.tryParse(match.group(2) ?? '');
      if (width != null && height != null) {
        _tileWidthController.text = width.toString();
        _tileHeightController.text = height.toString();
        // If we successfully parsed, we're done.
        return;
      }
    }

    // Fallback to default if no valid dimension pattern was found.
    _tileWidthController.text = '16';
    _tileHeightController.text = '16';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tileWidthController.dispose();
    _tileHeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ... This build method remains unchanged ...
    return AlertDialog(
      title: const Text('New Tileset'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'From image: ${widget.imagePath}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Tileset Name'),
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
              'name': _nameController.text.trim(),
              'tileWidth': int.tryParse(_tileWidthController.text) ?? 16,
              'tileHeight': int.tryParse(_tileHeightController.text) ?? 16,
            };
            Navigator.of(context).pop(result);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
