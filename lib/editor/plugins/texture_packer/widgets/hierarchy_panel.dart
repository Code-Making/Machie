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
    required this.onClose,
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
            child: Stack(
              children: [
                // Background Drop Zone (Covers area, handles drops to root)
                Positioned.fill(
                  child: HierarchyRootDropZone(
                    notifier: notifier,
                    rootNode: rootNode,
                    isBackground: true,
                  ),
                ),
                
                // Scrollable List
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildNodeList(rootNode, context, ref),
                      // Spacer to ensure bottom area is clickable for root drop
                      const SizedBox(height: 100), 
                    ],
                  ),
                ),
              ],
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
    
    // Explicitly handle empty non-root folders to show a drop target
    if (children.isEmpty && parent.id != 'root') {
      return Padding(
        padding: const EdgeInsets.only(left: 16.0),
        child: _EmptyFolderDropZone(parentId: parent.id, notifier: notifier),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          _ReorderDropZone(
            parentId: parent.id, 
            index: i, 
            notifier: notifier,
          ),
          _HierarchyNodeItem(
            node: children[i],
            notifier: notifier,
            depth: 0, 
          ),
        ],
        _ReorderDropZone(parentId: parent.id, index: children.length, notifier: notifier),
      ],
    );
  }
}

class HierarchyRootDropZone extends StatefulWidget {
  final TexturePackerNotifier notifier;
  final PackerItemNode rootNode;
  final bool isBackground;

  const HierarchyRootDropZone({
    super.key,
    required this.notifier,
    required this.rootNode,
    this.isBackground = false,
  });

  @override
  State<HierarchyRootDropZone> createState() => _HierarchyRootDropZoneState();
}

class _HierarchyRootDropZoneState extends State<HierarchyRootDropZone> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (draggedId) {
        if (draggedId == null) return false;
        final isAlreadyRoot = widget.rootNode.children.any((c) => c.id == draggedId);
        if (isAlreadyRoot) return false;
        
        setState(() => _isHovered = true);
        return true;
      },
      onLeave: (_) => setState(() => _isHovered = false),
      onAccept: (draggedId) {
        setState(() => _isHovered = false);
        widget.notifier.moveNode(draggedId, 'root', widget.rootNode.children.length);
      },
      builder: (context, candidates, rejected) {
        if (widget.isBackground) {
          if (_isHovered) {
            return Container(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.subdirectory_arrow_left, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text("Move to Root", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }
          return const SizedBox.expand(); 
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _HierarchyNodeItem extends ConsumerStatefulWidget {
  final PackerItemNode node;
  final TexturePackerNotifier notifier;
  final int depth;

  const _HierarchyNodeItem({
    required this.node,
    required this.notifier,
    this.depth = 0,
  });

  @override
  ConsumerState<_HierarchyNodeItem> createState() => _HierarchyNodeItemState();
}

class _HierarchyNodeItemState extends ConsumerState<_HierarchyNodeItem> {
  bool _isHovered = false;
  bool _isExpanded = true; 

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isContainer = node.type == PackerItemType.folder || node.type == PackerItemType.animation;

    Widget content = _buildTile(context, ref);

    if (isContainer) {
      content = DragTarget<String>(
        onWillAccept: (draggedId) {
          if (draggedId == null || draggedId == node.id) return false;
          
          if (node.type == PackerItemType.animation) {
             final draggedNode = _findNodeInTree(widget.notifier.project.tree, draggedId);
             if (draggedNode?.type != PackerItemType.sprite) return false;
          }
          
          setState(() => _isHovered = true);
          return true;
        },
        onLeave: (_) => setState(() => _isHovered = false),
        onAccept: (draggedId) {
          setState(() => _isHovered = false);
          widget.notifier.moveNode(draggedId, node.id, node.children.length);
        },
        builder: (context, candidates, rejected) {
          return Container(
            decoration: BoxDecoration(
              color: _isHovered 
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.2) 
                  : Colors.transparent,
              border: _isHovered 
                  ? Border.all(color: Theme.of(context).colorScheme.primary) 
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: content,
          );
        },
      );
    }

    content = LongPressDraggable<String>(
      data: node.id,
      feedback: Material(
        elevation: 4,
        color: Colors.transparent,
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.drag_indicator),
              const SizedBox(width: 8),
              Text(node.name),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: content),
      child: content,
    );

    if (isContainer && _isExpanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: _buildChildrenList(),
          ),
        ],
      );
    }

    return content;
  }

  Widget _buildChildrenList() {
    final children = widget.node.children;
    if (children.isEmpty) {
      return _EmptyFolderDropZone(parentId: widget.node.id, notifier: widget.notifier);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          _ReorderDropZone(parentId: widget.node.id, index: i, notifier: widget.notifier),
          _HierarchyNodeItem(
            node: children[i], 
            notifier: widget.notifier,
            depth: widget.depth + 1,
          ),
        ],
        _ReorderDropZone(parentId: widget.node.id, index: children.length, notifier: widget.notifier),
      ],
    );
  }

  Widget _buildTile(BuildContext context, WidgetRef ref) {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final isSelected = widget.node.id == selectedNodeId;
    final isContainer = widget.node.type == PackerItemType.folder || widget.node.type == PackerItemType.animation;

    IconData getIcon() {
      switch (widget.node.type) {
        case PackerItemType.folder: return _isExpanded ? Icons.folder_open : Icons.folder;
        case PackerItemType.sprite: return Icons.image_outlined;
        case PackerItemType.animation: return Icons.movie_outlined;
      }
    }

    return ListTile(
      leading: GestureDetector(
        onTap: isContainer ? () => setState(() => _isExpanded = !_isExpanded) : null,
        child: Icon(getIcon(), size: 20, 
          color: widget.node.type == PackerItemType.folder ? Colors.yellow[700] : null
        ),
      ),
      title: Text(widget.node.name),
      dense: true,
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      onTap: () {
        ref.read(selectedNodeIdProvider.notifier).state = widget.node.id;
      },
      trailing: _buildContextMenu(context, ref),
    );
  }

  Widget _buildContextMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'rename') {
          final newName = await showTextInputDialog(context, title: 'Rename', initialValue: widget.node.name);
          if (newName != null && newName.trim().isNotEmpty) {
            widget.notifier.renameNode(widget.node.id, newName.trim());
          }
        } else if (value == 'delete') {
          final confirm = await showConfirmDialog(
            context,
            title: 'Delete "${widget.node.name}"?',
            content: 'This action cannot be undone.',
          );
          if (confirm) {
            if (ref.read(selectedNodeIdProvider) == widget.node.id) {
              ref.read(selectedNodeIdProvider.notifier).state = null;
            }
            widget.notifier.deleteNode(widget.node.id);
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
  
  PackerItemNode? _findNodeInTree(PackerItemNode root, String id) {
    if (root.id == id) return root;
    for (var child in root.children) {
      final found = _findNodeInTree(child, id);
      if (found != null) return found;
    }
    return null;
  }
}

class _ReorderDropZone extends StatefulWidget {
  final String parentId;
  final int index;
  final TexturePackerNotifier notifier;

  const _ReorderDropZone({
    required this.parentId,
    required this.index,
    required this.notifier,
  });

  @override
  State<_ReorderDropZone> createState() => _ReorderDropZoneState();
}

class _ReorderDropZoneState extends State<_ReorderDropZone> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (draggedId) {
        if (draggedId == null) return false;
        setState(() => _isHovered = true);
        return true;
      },
      onLeave: (_) => setState(() => _isHovered = false),
      onAccept: (draggedId) {
        setState(() => _isHovered = false);
        widget.notifier.moveNode(draggedId, widget.parentId, widget.index);
      },
      builder: (context, candidates, rejected) {
        if (!_isHovered && candidates.isEmpty) {
          return const SizedBox(height: 4.0);
        }

        return Container(
          height: 4.0,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }
}

class _EmptyFolderDropZone extends StatelessWidget {
  final String parentId;
  final TexturePackerNotifier notifier;

  const _EmptyFolderDropZone({required this.parentId, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (data) => data != null,
      onAccept: (nodeId) {
        notifier.moveNode(nodeId, parentId, 0);
      },
      builder: (context, candidates, rejected) {
        final isHovered = candidates.isNotEmpty;
        if (!isHovered) return const SizedBox(height: 10); 

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.primary, 
              style: BorderStyle.solid
            ),
            borderRadius: BorderRadius.circular(4),
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          ),
          child: Center(
            child: Text(
              "Drop here", 
              style: TextStyle(
                fontSize: 10, 
                color: Theme.of(context).colorScheme.primary
              ),
            ),
          ),
        );
      },
    );
  }
}