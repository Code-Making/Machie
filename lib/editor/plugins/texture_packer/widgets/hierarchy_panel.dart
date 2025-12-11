import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';

class HierarchyPanel extends ConsumerWidget {
  final String tabId;
  const HierarchyPanel({super.key, required this.tabId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootNode = ref.watch(texturePackerNotifierProvider(tabId).select((p) => p.tree));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('Sprites & Animations', style: Theme.of(context).textTheme.titleMedium),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: rootNode.children
                .map((node) => _PackerNodeItem(node: node, tabId: tabId))
                .toList(),
          ),
        ),
        const Divider(height: 1),
        // TODO: Add buttons for 'New Folder', 'New Animation'
      ],
    );
  }
}

class _PackerNodeItem extends ConsumerWidget {
  final PackerItemNode node;
  final String tabId;
  final int depth;

  const _PackerNodeItem({
    required this.node,
    required this.tabId,
    this.depth = 0,
  });

  IconData _getIcon() {
    switch (node.type) {
      case PackerItemType.folder:
        return Icons.folder_outlined;
      case PackerItemType.sprite:
        return Icons.image_outlined;
      case PackerItemType.animation:
        return Icons.movie_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final isSelected = node.id == selectedNodeId;

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
          trailing: IconButton(
            icon: const Icon(Icons.more_vert, size: 20),
            onPressed: () {
              // TODO: Implement context menu (Rename, Delete, Create...)
            },
          ),
        ),
        if (node.children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Column(
              children: node.children
                  .map((child) => _PackerNodeItem(node: child, tabId: tabId, depth: depth + 1))
                  .toList(),
            ),
          )
      ],
    );
  }
}