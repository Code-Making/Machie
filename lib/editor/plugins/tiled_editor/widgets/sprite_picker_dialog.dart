import 'package:flutter/material.dart';

class SpritePickerDialog extends StatefulWidget {
  final List<String> spriteNames;
  const SpritePickerDialog({super.key, required this.spriteNames});

  @override
  State<SpritePickerDialog> createState() => _SpritePickerDialogState();
}

class _SpritePickerDialogState extends State<SpritePickerDialog> {
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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
              autofocus: true,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}