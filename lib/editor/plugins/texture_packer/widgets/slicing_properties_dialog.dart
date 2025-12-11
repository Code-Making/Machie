import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';

class SlicingPropertiesDialog extends ConsumerStatefulWidget {
  final String tabId;

  const SlicingPropertiesDialog({super.key, required this.tabId});
  
  static Future<void> show(BuildContext context, String tabId) {
    return showDialog(
      context: context,
      builder: (_) => SlicingPropertiesDialog(tabId: tabId),
    );
  }

  @override
  ConsumerState<SlicingPropertiesDialog> createState() => _SlicingPropertiesDialogState();
}

class _SlicingPropertiesDialogState extends ConsumerState<SlicingPropertiesDialog> {
  late final TextEditingController _tileWidthController;
  late final TextEditingController _tileHeightController;
  late final TextEditingController _marginController;
  late final TextEditingController _paddingController;
  late int _activeIndex;

  @override
  void initState() {
    super.initState();
    _activeIndex = ref.read(activeSourceImageIndexProvider);
    final config = ref.read(texturePackerNotifierProvider(widget.tabId)
        .select((p) => p.sourceImages[_activeIndex].slicing));

    _tileWidthController = TextEditingController(text: config.tileWidth.toString());
    _tileHeightController = TextEditingController(text: config.tileHeight.toString());
    _marginController = TextEditingController(text: config.margin.toString());
    _paddingController = TextEditingController(text: config.padding.toString());
  }
  
  @override
  void dispose() {
    _tileWidthController.dispose();
    _tileHeightController.dispose();
    _marginController.dispose();
    _paddingController.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final newConfig = SlicingConfig(
      tileWidth: int.tryParse(_tileWidthController.text) ?? 16,
      tileHeight: int.tryParse(_tileHeightController.text) ?? 16,
      margin: int.tryParse(_marginController.text) ?? 0,
      padding: int.tryParse(_paddingController.text) ?? 0,
    );
    ref.read(texturePackerNotifierProvider(widget.tabId).notifier)
       .updateSlicingConfig(_activeIndex, newConfig);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Slicing Properties'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _tileWidthController, decoration: const InputDecoration(labelText: 'Tile Width (px)'), keyboardType: TextInputType.number),
            TextField(controller: _tileHeightController, decoration: const InputDecoration(labelText: 'Tile Height (px)'), keyboardType: TextInputType.number),
            TextField(controller: _marginController, decoration: const InputDecoration(labelText: 'Margin (px)'), keyboardType: TextInputType.number),
            TextField(controller: _paddingController, decoration: const InputDecoration(labelText: 'Padding (px)'), keyboardType: TextInputType.number),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _onConfirm, child: const Text('Apply')),
      ],
    );
  }
}