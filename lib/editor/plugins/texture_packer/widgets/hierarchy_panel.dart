import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart'; // For confirmation dialog

class HierarchyPanel extends ConsumerWidget {
  final TexturePackerNotifier notifier;
  final VoidCallback onClose;

  const HierarchyPanel({
    super.key, 
    required this.notifier,
    required this.onClose
  });

  Future<void> _showCreateDialog(BuildContext context, PackerItemType type, {String? parentId}) async {
    final String title = type == PackerItemType.folder ? 'New Folder' : 'New Animation';
    final name = await showTextInputDialog(context, title: title);
    if (name != null && name.trim().isNotEmpty) {
      notifier.createNode(type: type, name: name.trim(), parentId: parentId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootNode = notifier.project.tree;

    return Material(
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Title and Close Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Text('Sprites & Animations', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                  tooltip: 'Close Panel',
                )
              ],
            ),
          ),
          const Divider(height: 1),
          // Tree View
          Expanded(
            child: ListView(
              children: rootNode.children
                  .map((node) => _PackerNodeItem(node: node, notifier: notifier))
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showCreateDialog(context, PackerItemType.folder),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Folder'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showCreateDialog(context, PackerItemType.animation),
                    icon: const Icon(Icons.movie_creation_outlined),
                    label: const Text('Animation'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackerNodeItem extends ConsumerWidget {
  final PackerItemNode node;
  final TexturePackerNotifier notifier;
  final int depth;

  const _PackerNodeItem({
    required this.node,
    required this.notifier,
    this.depth = 0,
  });

  IconData _getIcon() {
    switch (node.type) {
      case PackerItemType.folder: return Icons.folder_outlined;
      case PackerItemType.sprite: return Icons.image_outlined;
      case PackerItemType.animation: return Icons.movie_outlined;
    }
  }

  // --- HIERARCHY PANEL REFACTOR: Context Menu Actions ---
  Future<void> _renameNode(BuildContext context) async {
    final newName = await showTextInputDialog(
      context,
      title: 'Rename Item',
      initialValue: node.name,
    );
    if (newName != null && newName.trim().isNotEmpty && newName != node.name) {
      notifier.renameNode(node.id, newName.trim());
    }
  }

  Future<void> _deleteNode(BuildContext context, WidgetRef ref) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete "${node.name}"?',
      content: 'Are you sure you want to delete this item? This action cannot be undone from here.',
    );
    if (confirm) {
      // If the deleted node was the selected one, deselect it.
      if (ref.read(selectedNodeIdProvider) == node.id) {
        ref.read(selectedNodeIdProvider.notifier).state = null;
      }
      notifier.deleteNode(node.id);
    }
  }
  // --- END REFACTOR ---

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final isSelected = node.id == selectedNodeId;
    
    // Using PopupMenuButton for a clean context menu
    final contextMenu = PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'rename') {
          _renameNode(context);
        } else if (value == 'delete') {
          _deleteNode(context, ref);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename')),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.redAccent), title: Text('Delete')),
        ),
      ],
      icon: const Icon(Icons.more_vert, size: 20),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: Icon(_getIcon()),
          ),
          title: Text(node.name),
          selected: isSelected,
          dense: true,
          onTap: () {
            ref.read(selectedNodeIdProvider.notifier).state = node.id;
          },
          trailing: contextMenu, // Use the new PopupMenuButton
        ),
        if (node.children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Column(
              children: node.children
                  .map((child) => _PackerNodeItem(node: child, notifier: notifier, depth: depth + 1))
                  .toList(),
            ),
          )
      ],
    );
  }
}