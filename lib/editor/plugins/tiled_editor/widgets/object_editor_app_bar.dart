// lib/editor/plugins/tiled_editor/widgets/object_editor_app_bar.dart

import 'package:flutter/material.dart';

import '../../../../command/command_widgets.dart';
import '../tiled_editor_plugin.dart';

class ObjectEditorAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final VoidCallback onExit;
  final bool isSnapToGridEnabled;
  final VoidCallback onToggleSnapToGrid;
  final bool isObjectSelected;
  final VoidCallback onInspectObject;
  final VoidCallback onDeleteObject;
  final bool showFinishShapeButton;
  final VoidCallback onFinishShape;

  const ObjectEditorAppBar({
    super.key,
    required this.onExit,
    required this.isSnapToGridEnabled,
    required this.onToggleSnapToGrid,
    required this.isObjectSelected,
    required this.onInspectObject,
    required this.onDeleteObject,
    required this.showFinishShapeButton,
    required this.onFinishShape,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Exit Object Mode (Pan/Zoom)',
        onPressed: onExit,
      ),
      title:
          showFinishShapeButton
              ? TextButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Finish'),
                onPressed: onFinishShape,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                ),
              )
              : const SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: CommandToolbar(
                  position: TiledEditorPlugin.objectToolsToolbar,
                ),
              ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          tooltip: 'Delete Selected Object(s)',
          onPressed: isObjectSelected ? onDeleteObject : null,
        ),
        IconButton(
          icon: const Icon(Icons.manage_search),
          tooltip: 'Inspect Selected Object',
          color: isObjectSelected ? theme.colorScheme.primary : null,
          onPressed: isObjectSelected ? onInspectObject : null,
        ),
        IconButton(
          icon: const Icon(Icons.grid_on_outlined),
          tooltip: 'Snap to Grid',
          color: isSnapToGridEnabled ? theme.colorScheme.primary : null,
          onPressed: onToggleSnapToGrid,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
