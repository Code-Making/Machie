import 'package:flutter/material.dart';

class SlicingAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onExit;
  final bool hasSelection;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const SlicingAppBar({
    super.key,
    required this.onExit,
    required this.hasSelection,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Exit Slicing Mode (Pan/Zoom)',
        onPressed: onExit,
      ),
      title: const Text('Select Sprite Area'),
      actions: [
        if (hasSelection) ...[
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel Selection',
            onPressed: onCancel,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Create Sprite'),
            onPressed: onConfirm,
          ),
          const SizedBox(width: 16),
        ]
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}