// lib/editor/plugins/tiled_editor/widgets/paint_editor_app_bar.dart

import 'package:flutter/material.dart';
import '../../../../command/command_widgets.dart';
import '../tiled_editor_plugin.dart';

class PaintEditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onExit;

  const PaintEditorAppBar({
    super.key,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Exit Paint Mode (Pan/Zoom)',
        onPressed: onExit,
      ),
      title: const SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: CommandToolbar(
          position: TiledEditorPlugin.paintToolsToolbar,
        ),
      ),
      actions: const [
        // Actions can be added here via command system if needed later
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}