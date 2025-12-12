import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart';

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Text('Hierarchy', style: Theme.of(context).textTheme.titleMedium),
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
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildNodeList(rootNode, context, ref),
              ),
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
                    label: const Text('Anim'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeList(PackerItemNode parent, BuildContext context, WidgetRef ref) {
    final children = parent.children;
    if (children.isEmpty) {
      return _DropZone(
        parentId: parent.id,
        index: 0,
        notifier: notifier,
        isEmptyFolder: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          _DropZone(parentId: parent.id, index: i, notifier: notifier),
          _DraggableNodeItem(
            node: children[i],
            notifier: notifier,
            depth: 0, 
          ),
        ],
        _DropZone(parentId: parent.id, index: children.length, notifier: notifier),
      ],
    );
  }
}

class _DraggableNodeItem extends ConsumerWidget {
  final PackerItemNode node;
  final TexturePackerNotifier notifier;
  final int depth;

  const _DraggableNodeItem({
    required this.node,
    required this.notifier,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LongPressDraggable<String>(
      data: node.id,
      feedback: Material(
        elevation: 4,
        color: Colors.transparent,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.drag_handle),
              const SizedBox(width: 8),
              Text(node.name),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildTile(context, ref, isDragging: true),
      ),
      child: _buildDragTargetWrapper(context, ref),
    );
  }

  Widget _buildDragTargetWrapper(BuildContext context, WidgetRef ref) {
    if (node.type != PackerItemType.folder) {
      return _buildTile(context, ref);
    }

    return DragTarget<String>(
      onWillAccept: (incomingId) {
        if (incomingId == null || incomingId == node.id) return false;
        return true; 
      },
      onAccept: (incomingId) {
        notifier.moveNode(incomingId, node.id, node.children.length);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return Container(
          decoration: isHovered
              ? BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: _buildTile(context, ref),
        );
      },
    );
  }

  Widget _buildTile(BuildContext context, WidgetRef ref, {bool isDragging = false}) {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final isSelected = node.id == selectedNodeId;

    IconData getIcon() {
      switch (node.type) {
        case PackerItemType.folder: return Icons.folder_outlined;
        case PackerItemType.sprite: return Icons.image_outlined;
        case PackerItemType.animation: return Icons.movie_outlined;
      }
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 16.0),
          child: ListTile(
            leading: Icon(getIcon(), size: 20),
            title: Text(node.name),
            dense: true,
            selected: isSelected,
            visualDensity: VisualDensity.compact,
            onTap: () {
              ref.read(selectedNodeIdProvider.notifier).state = node.id;
            },
            trailing: _buildContextMenu(context, ref),
          ),
        ),
        if (node.children.isNotEmpty)
          Column(
            children: [
              for (int i = 0; i < node.children.length; i++) ...[
                _DropZone(
                  parentId: node.id, 
                  index: i, 
                  notifier: notifier, 
                  indent: (depth + 1) * 16.0
                ),
                _DraggableNodeItem(
                  node: node.children[i],
                  notifier: notifier,
                  depth: depth + 1,
                ),
              ],
              _DropZone(
                parentId: node.id, 
                index: node.children.length, 
                notifier: notifier,
                indent: (depth + 1) * 16.0
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildContextMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'rename') {
          final newName = await showTextInputDialog(context, title: 'Rename', initialValue: node.name);
          if (newName != null && newName.trim().isNotEmpty) {
            notifier.renameNode(node.id, newName.trim());
          }
        } else if (value == 'delete') {
          final confirm = await showConfirmDialog(
            context,
            title: 'Delete "${node.name}"?',
            content: 'This action cannot be undone.',
          );
          if (confirm) {
            if (ref.read(selectedNodeIdProvider) == node.id) {
              ref.read(selectedNodeIdProvider.notifier).state = null;
            }
            notifier.deleteNode(node.id);
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
      ],
      icon: const Icon(Icons.more_vert, size: 16),
    );
  }
}

class _DropZone extends StatelessWidget {
  final String parentId;
  final int index;
  final TexturePackerNotifier notifier;
  final double indent;
  final bool isEmptyFolder;

  const _DropZone({
    required this.parentId,
    required this.index,
    required this.notifier,
    this.indent = 0.0,
    this.isEmptyFolder = false,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (data) => data != null,
      onAccept: (nodeId) {
        notifier.moveNode(nodeId, parentId, index);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        
        if (isEmptyFolder) {
          if (!isHovered) return const SizedBox(height: 0); 
          return Container(
            margin: const EdgeInsets.all(8),
            height: 40,
            decoration: BoxDecoration(
              // FIX: Replaced dashed with solid, as standard Flutter doesn't have dashed enum
              border: Border.all(color: Theme.of(context).colorScheme.primary, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(child: Text("Drop inside folder", style: TextStyle(fontSize: 10))),
          );
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: isHovered ? 4.0 : 4.0,
          margin: EdgeInsets.only(left: indent),
          width: double.infinity,
          decoration: BoxDecoration(
            color: isHovered ? Theme.of(context).colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }
}