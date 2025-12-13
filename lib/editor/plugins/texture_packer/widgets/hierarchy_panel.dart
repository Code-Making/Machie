import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart';

class HierarchyPanel extends ConsumerStatefulWidget {
  final TexturePackerNotifier notifier;
  final VoidCallback onClose;

  const HierarchyPanel({
    super.key,
    required this.notifier,
    required this.onClose,
  });

  @override
  ConsumerState<HierarchyPanel> createState() => _HierarchyPanelState();
}

class _HierarchyPanelState extends ConsumerState<HierarchyPanel> {
  // Track expanded nodes locally to flatten the tree
  final Set<String> _expandedIds = {};

  // Auto-expand root children initially
  @override
  void initState() {
    super.initState();
    // Optional: Pre-expand root level items
    final root = widget.notifier.project.tree;
    for(final child in root.children) {
      if (child.type != PackerItemType.sprite) {
        _expandedIds.add(child.id);
      }
    }
  }

  Future<void> _showCreateDialog(BuildContext context, PackerItemType type) async {
    final String title = type == PackerItemType.folder ? 'New Folder' : 'New Animation';
    final name = await showTextInputDialog(context, title: title);
    if (name != null && name.trim().isNotEmpty) {
      // Create at root by default
      widget.notifier.createNode(type: type, name: name.trim(), parentId: 'root');
    }
  }

  void _toggleExpansion(String nodeId) {
    setState(() {
      if (_expandedIds.contains(nodeId)) {
        _expandedIds.remove(nodeId);
      } else {
        _expandedIds.add(nodeId);
      }
    });
  }

  /// Flattens the recursive tree into a linear list of widgets (DropZones and Items)
  List<Widget> _buildFlatList(PackerItemNode root) {
    final List<Widget> widgets = [];

    void traverse(PackerItemNode parent, int depth) {
      final children = parent.children;
      final double indent = depth * 16.0;

      // 1. If empty folder (and not root), show "Drop Here" hint
      if (children.isEmpty && parent.id != 'root') {
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent),
          child: _EmptyFolderDropZone(
            parentId: parent.id, 
            notifier: widget.notifier
          ),
        ));
        return;
      }

      // 2. Iterate children
      for (int i = 0; i < children.length; i++) {
        final child = children[i];
        
        // Add DropZone BEFORE item (for reordering above)
        widgets.add(_ReorderDropZone(
          parentId: parent.id, 
          index: i, 
          notifier: widget.notifier,
          indent: indent,
        ));

        // Add the Item itself
        final isContainer = child.type == PackerItemType.folder || child.type == PackerItemType.animation;
        final isExpanded = _expandedIds.contains(child.id);

        widgets.add(_HierarchyNodeItem(
          node: child,
          notifier: widget.notifier,
          depth: depth,
          isExpanded: isExpanded,
          onToggleExpand: () => _toggleExpansion(child.id),
        ));

        // Recurse if expanded
        if (isContainer && isExpanded) {
          traverse(child, depth + 1);
        }
      }

      // 3. Final DropZone at end of this list (for reordering to bottom)
      if (children.isNotEmpty) {
        widgets.add(_ReorderDropZone(
          parentId: parent.id, 
          index: children.length, 
          notifier: widget.notifier,
          indent: indent,
        ));
      }
    }

    traverse(root, 0);
    
    // 4. Add global "Move to Root" zone at the very bottom
    widgets.add(const SizedBox(height: 16));
    widgets.add(HierarchyRootDropZone(notifier: widget.notifier, rootNode: root));
    widgets.add(const SizedBox(height: 32)); // Bottom padding

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final rootNode = widget.notifier.project.tree;
    final flatList = _buildFlatList(rootNode);

    return Material(
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Text('Hierarchy', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                  tooltip: 'Close Panel',
                )
              ],
            ),
          ),
          const Divider(height: 1),

          // Flat List View
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: flatList.length,
              itemBuilder: (context, index) => flatList[index],
            ),
          ),

          const Divider(height: 1),

          // Toolbar
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
}

// -----------------------------------------------------------------------------
// Component Widgets (Non-Recursive)
// -----------------------------------------------------------------------------

class HierarchyRootDropZone extends StatefulWidget {
  final TexturePackerNotifier notifier;
  final PackerItemNode rootNode;

  const HierarchyRootDropZone({
    super.key,
    required this.notifier,
    required this.rootNode,
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
        // Don't accept if already at root
        if (widget.rootNode.children.any((c) => c.id == draggedId)) return false;
        
        setState(() => _isHovered = true);
        return true;
      },
      onLeave: (_) => setState(() => _isHovered = false),
      onAccept: (draggedId) {
        setState(() => _isHovered = false);
        widget.notifier.moveNode(draggedId, 'root', widget.rootNode.children.length);
      },
      builder: (context, candidates, rejected) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _isHovered ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
            border: _isHovered ? Border.all(color: Theme.of(context).colorScheme.primary) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          height: 50,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.subdirectory_arrow_left, 
                color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
              const SizedBox(width: 8),
              Text(
                "Move to Root",
                style: TextStyle(color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HierarchyNodeItem extends ConsumerStatefulWidget {
  final PackerItemNode node;
  final TexturePackerNotifier notifier;
  final int depth;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const _HierarchyNodeItem({
    required this.node,
    required this.notifier,
    required this.depth,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  ConsumerState<_HierarchyNodeItem> createState() => _HierarchyNodeItemState();
}

class _HierarchyNodeItemState extends ConsumerState<_HierarchyNodeItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isContainer = node.type == PackerItemType.folder || node.type == PackerItemType.animation;

    // Base Tile
    Widget content = _buildTile(context, ref);

    // If container, wrap in "Drop Inside" target
    if (isContainer) {
      content = DragTarget<String>(
        onWillAccept: (draggedId) {
          if (draggedId == null || draggedId == node.id) return false;
          
          // Type checks
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
          // Auto-expand on drop
          if (!widget.isExpanded) widget.onToggleExpand();
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
            ),
            child: content,
          );
        },
      );
    }

    // Wrap in Draggable
    return LongPressDraggable<String>(
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
  }

  Widget _buildTile(BuildContext context, WidgetRef ref) {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final isSelected = widget.node.id == selectedNodeId;
    final isContainer = widget.node.type == PackerItemType.folder || widget.node.type == PackerItemType.animation;

    IconData getIcon() {
      switch (widget.node.type) {
        case PackerItemType.folder: return widget.isExpanded ? Icons.folder_open : Icons.folder;
        case PackerItemType.sprite: return Icons.image_outlined;
        case PackerItemType.animation: return Icons.movie_outlined;
      }
    }

    return Padding(
      // Visual indentation
      padding: EdgeInsets.only(left: widget.depth * 16.0),
      child: ListTile(
        leading: GestureDetector(
          onTap: isContainer ? widget.onToggleExpand : null,
          child: Icon(getIcon(), size: 20, 
            color: widget.node.type == PackerItemType.folder ? Colors.yellow[700] : null
          ),
        ),
        title: Text(widget.node.name),
        dense: true,
        selected: isSelected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4), // Reduce padding
        onTap: () {
          ref.read(selectedNodeIdProvider.notifier).state = widget.node.id;
        },
        trailing: _buildContextMenu(context),
      ),
    );
  }

  Widget _buildContextMenu(BuildContext context) {
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
  final double indent;

  const _ReorderDropZone({
    required this.parentId,
    required this.index,
    required this.notifier,
    required this.indent,
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
        // Basic check: don't show drop zone if self or sibling logic (optional optimization)
        setState(() => _isHovered = true);
        return true;
      },
      onLeave: (_) => setState(() => _isHovered = false),
      onAccept: (draggedId) {
        setState(() => _isHovered = false);
        widget.notifier.moveNode(draggedId, widget.parentId, widget.index);
      },
      builder: (context, candidates, rejected) {
        // Always take up a tiny bit of space so it can be hit, but only visible on hover
        if (!_isHovered && candidates.isEmpty) {
          return const SizedBox(height: 6.0); 
        }

        return Container(
          height: 6.0,
          margin: EdgeInsets.only(left: widget.indent),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(3),
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
        // Always visible to indicate empty folder state
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(
              color: isHovered ? Theme.of(context).colorScheme.primary : Colors.grey.withOpacity(0.5), 
              style: isHovered ? BorderStyle.solid : BorderStyle.none
            ),
            color: isHovered 
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              "Empty - Drop Items Here", 
              style: TextStyle(
                fontSize: 10, 
                fontStyle: FontStyle.italic,
                color: isHovered 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).textTheme.bodySmall?.color
              ),
            ),
          ),
        );
      },
    );
  }
}