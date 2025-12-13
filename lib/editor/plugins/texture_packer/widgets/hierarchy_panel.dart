// lib/editor/plugins/texture_packer/widgets/hierarchy_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart';

/// Internal model to flatten the tree for the ListView
class _FlatNode {
  final PackerItemNode node;
  final int depth;
  final String parentId;
  final int indexInParent;

  _FlatNode({
    required this.node,
    required this.depth,
    required this.parentId,
    required this.indexInParent,
  });
}

enum _DropPosition { above, inside, below }

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
  // Store expanded state locally by ID
  final Set<String> _expandedIds = {'root'};

  void _toggleExpansion(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  /// Flattens the recursive tree into a linear list based on expansion state.
  List<_FlatNode> _buildFlatList() {
    final List<_FlatNode> flatList = [];
    final root = widget.notifier.project.tree;

    void traverse(PackerItemNode node, int depth, String parentId, int index) {
      // Don't add the invisible 'root' container itself to the UI list
      if (node.id != 'root') {
        flatList.add(_FlatNode(
          node: node,
          depth: depth,
          parentId: parentId,
          indexInParent: index,
        ));
      }

      // If root (always expanded) or expanded folder/anim, process children
      if (node.id == 'root' || _expandedIds.contains(node.id)) {
        for (int i = 0; i < node.children.length; i++) {
          traverse(node.children[i], node.id == 'root' ? 0 : depth + 1, node.id, i);
        }
      }
    }

    traverse(root, 0, 'root', 0);
    return flatList;
  }

  Future<void> _showCreateDialog(PackerItemType type, {String? parentId}) async {
    final String title = type == PackerItemType.folder ? 'New Folder' : 'New Animation';
    final name = await showTextInputDialog(context, title: title);
    if (name != null && name.trim().isNotEmpty) {
      widget.notifier.createNode(
        type: type, 
        name: name.trim(), 
        parentId: parentId ?? ref.read(selectedNodeIdProvider) ?? 'root'
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final flatList = _buildFlatList();

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
                IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
              ],
            ),
          ),
          const Divider(height: 1),

          // Tree View
          Expanded(
            child: GestureDetector(
              // Clicking empty space deselects
              onTap: () => ref.read(selectedNodeIdProvider.notifier).state = null,
              child: ListView.builder(
                itemCount: flatList.length + 1, // +1 for the empty space drop zone at bottom
                itemBuilder: (context, index) {
                  if (index == flatList.length) {
                    // Bottom "Root" drop zone
                    return _HierarchyRootDropZone(
                      notifier: widget.notifier, 
                      rootNode: widget.notifier.project.tree
                    );
                  }

                  final item = flatList[index];
                  return _HierarchyItemRow(
                    key: ValueKey(item.node.id),
                    flatNode: item,
                    isExpanded: _expandedIds.contains(item.node.id),
                    onToggleExpand: () => _toggleExpansion(item.node.id),
                    notifier: widget.notifier,
                  );
                },
              ),
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
                    onPressed: () => _showCreateDialog(PackerItemType.folder),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Folder'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showCreateDialog(PackerItemType.animation),
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

class _HierarchyItemRow extends ConsumerStatefulWidget {
  final _FlatNode flatNode;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final TexturePackerNotifier notifier;

  const _HierarchyItemRow({
    super.key,
    required this.flatNode,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.notifier,
  });

  @override
  ConsumerState<_HierarchyItemRow> createState() => _HierarchyItemRowState();
}

class _HierarchyItemRowState extends ConsumerState<_HierarchyItemRow> {
  _DropPosition? _dropPosition;

  bool get _isContainer => 
      widget.flatNode.node.type == PackerItemType.folder || 
      widget.flatNode.node.type == PackerItemType.animation;

  @override
  Widget build(BuildContext context) {
    final node = widget.flatNode.node;
    final isSelected = ref.watch(selectedNodeIdProvider) == node.id;
    final theme = Theme.of(context);

    // Visual Content
    Widget content = Container(
      height: 32,
      padding: EdgeInsets.only(left: widget.flatNode.depth * 16.0 + 8.0),
      color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.3) : null,
      child: Row(
        children: [
          // Expander Icon
          if (_isContainer)
            GestureDetector(
              onTap: widget.onToggleExpand,
              child: Icon(
                widget.isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                size: 20,
              ),
            )
          else
            const SizedBox(width: 20),
          
          // Type Icon
          Icon(
            _getIcon(),
            size: 18,
            color: node.type == PackerItemType.folder ? Colors.yellow[700] : null,
          ),
          const SizedBox(width: 8),
          
          // Name
          Expanded(
            child: Text(
              node.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? theme.colorScheme.primary : null,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
          
          // Context Menu
          _buildContextMenu(),
        ],
      ),
    );

    // Wrap with Feedback Painter for Drop Targets
    if (_dropPosition != null) {
      content = CustomPaint(
        foregroundPainter: _DropIndicatorPainter(
          position: _dropPosition!,
          color: theme.colorScheme.primary,
        ),
        child: content,
      );
    }

    // Wrap with Draggable
    final draggable = LongPressDraggable<String>(
      data: node.id,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(8),
          color: theme.cardColor,
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

    // Wrap with DragTarget
    return DragTarget<String>(
      onWillAccept: (draggedId) {
        if (draggedId == null || draggedId == node.id) return false;
        // NOTE: Cycle detection is strict in Notifier, but we can do a quick check here if we had access to tree
        return true;
      },
      onMove: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final localPos = renderBox.globalToLocal(details.offset);
        final height = renderBox.size.height;
        
        // Define Hit Zones
        // Top 25% -> Above
        // Bottom 25% -> Below
        // Middle -> Inside (if container)
        
        _DropPosition newPos;
        if (localPos.dy < height * 0.25) {
          newPos = _DropPosition.above;
        } else if (localPos.dy > height * 0.75) {
          newPos = _DropPosition.below;
        } else {
          // Middle
          newPos = _isContainer ? _DropPosition.inside : _DropPosition.below;
        }

        if (_dropPosition != newPos) {
          setState(() => _dropPosition = newPos);
        }
      },
      onLeave: (_) => setState(() => _dropPosition = null),
      onAccept: (draggedId) {
        if (_dropPosition == null) return;
        
        final targetParent = widget.flatNode.parentId;
        final targetIndex = widget.flatNode.indexInParent;

        switch (_dropPosition!) {
          case _DropPosition.above:
            // Move into same parent, at current index
            widget.notifier.moveNode(draggedId, targetParent, targetIndex);
            break;
          case _DropPosition.below:
            // Move into same parent, at current index + 1
            widget.notifier.moveNode(draggedId, targetParent, targetIndex + 1);
            break;
          case _DropPosition.inside:
            // Move into THIS node, at end (or 0)
            widget.notifier.moveNode(draggedId, node.id, 0);
            if (!widget.isExpanded) widget.onToggleExpand();
            break;
        }
        setState(() => _dropPosition = null);
      },
      builder: (ctx, candidates, rejects) {
        // We handle visual feedback via onMove state + CustomPainter
        return InkWell(
          onTap: () => ref.read(selectedNodeIdProvider.notifier).state = node.id,
          child: draggable,
        );
      },
    );
  }

  IconData _getIcon() {
    switch (widget.flatNode.node.type) {
      case PackerItemType.folder: return widget.isExpanded ? Icons.folder_open : Icons.folder;
      case PackerItemType.sprite: return Icons.image_outlined;
      case PackerItemType.animation: return Icons.movie_creation_outlined;
    }
  }

  Widget _buildContextMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16),
      onSelected: (value) async {
        if (value == 'rename') {
          final newName = await showTextInputDialog(context, title: 'Rename', initialValue: widget.flatNode.node.name);
          if (newName != null && newName.trim().isNotEmpty) {
            widget.notifier.renameNode(widget.flatNode.node.id, newName.trim());
          }
        } else if (value == 'delete') {
          final confirm = await showConfirmDialog(context, title: 'Delete?', content: 'Cannot be undone.');
          if (confirm) widget.notifier.deleteNode(widget.flatNode.node.id);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    );
  }
}

class _HierarchyRootDropZone extends StatefulWidget {
  final TexturePackerNotifier notifier;
  final PackerItemNode rootNode;

  const _HierarchyRootDropZone({required this.notifier, required this.rootNode});

  @override
  State<_HierarchyRootDropZone> createState() => _HierarchyRootDropZoneState();
}

class _HierarchyRootDropZoneState extends State<_HierarchyRootDropZone> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      // Corrected: Use onWillAccept to detect entry and set hover state
      onWillAccept: (data) {
        if (data != null) {
          setState(() => _isHovered = true);
          return true;
        }
        return false;
      },
      onLeave: (_) => setState(() => _isHovered = false),
      onAccept: (draggedId) {
        setState(() => _isHovered = false);
        // Move to root, at the very end
        widget.notifier.moveNode(draggedId, 'root', widget.rootNode.children.length);
      },
      builder: (context, candidates, rejected) {
        return Container(
          height: 100, // Large hit area at bottom
          color: _isHovered ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
          alignment: Alignment.center,
          child: _isHovered 
            ? const Text("Move to Root", style: TextStyle(color: Colors.grey)) 
            : null,
        );
      },
    );
  }
}

class _DropIndicatorPainter extends CustomPainter {
  final _DropPosition position;
  final Color color;

  _DropIndicatorPainter({required this.position, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    switch (position) {
      case _DropPosition.above:
        canvas.drawLine(Offset(0, 1), Offset(size.width, 1), paint);
        break;
      case _DropPosition.below:
        canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), paint);
        break;
      case _DropPosition.inside:
        final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
        canvas.drawRect(rect, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _DropIndicatorPainter oldDelegate) {
    return oldDelegate.position != position || oldDelegate.color != color;
  }
}