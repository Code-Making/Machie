// lib/editor/plugins/texture_packer/widgets/source_images_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart';

// Reuse DropPosition enum and Painter logic if possible, or define locally
enum _SourceDropPos { above, inside, below }

class _FlatSourceNode {
  final SourceImageNode node;
  final int depth;
  final String parentId;
  final int indexInParent;

  _FlatSourceNode({
    required this.node,
    required this.depth,
    required this.parentId,
    required this.indexInParent,
  });
}

class SourceImagesPanel extends ConsumerStatefulWidget {
  final TexturePackerNotifier notifier;
  final VoidCallback onAddImage;
  final VoidCallback onClose;

  const SourceImagesPanel({
    super.key,
    required this.notifier,
    required this.onAddImage,
    required this.onClose,
  });

  @override
  ConsumerState<SourceImagesPanel> createState() => _SourceImagesPanelState();
}

class _SourceImagesPanelState extends ConsumerState<SourceImagesPanel> {
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

  List<_FlatSourceNode> _buildFlatList() {
    final List<_FlatSourceNode> flatList = [];
    final root = widget.notifier.project.sourceImagesRoot;

    void traverse(SourceImageNode node, int depth, String parentId, int index) {
      if (node.id != 'root') {
        flatList.add(_FlatSourceNode(
          node: node,
          depth: depth,
          parentId: parentId,
          indexInParent: index,
        ));
      }

      if (node.id == 'root' || _expandedIds.contains(node.id)) {
        for (int i = 0; i < node.children.length; i++) {
          traverse(node.children[i], node.id == 'root' ? 0 : depth + 1, node.id, i);
        }
      }
    }

    traverse(root, 0, 'root', 0);
    return flatList;
  }

  Future<void> _createFolder(BuildContext context) async {
    final name = await showTextInputDialog(context, title: 'New Folder');
    if (name != null && name.trim().isNotEmpty) {
      widget.notifier.addSourceNode(
        name: name.trim(),
        type: SourceNodeType.folder,
        parentId: 'root',
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
                Text('Source Images', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
              ],
            ),
          ),
          const Divider(height: 1),

          // List
          Expanded(
            child: ListView.builder(
              itemCount: flatList.length + 1,
              itemBuilder: (context, index) {
                if (index == flatList.length) {
                  return _SourceRootDropZone(notifier: widget.notifier, rootNode: widget.notifier.project.sourceImagesRoot);
                }
                
                final item = flatList[index];
                return _SourceItemRow(
                  key: ValueKey(item.node.id),
                  flatNode: item,
                  isExpanded: _expandedIds.contains(item.node.id),
                  onToggleExpand: () => _toggleExpansion(item.node.id),
                  notifier: widget.notifier,
                );
              },
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
                    onPressed: () => _createFolder(context),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Folder'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onAddImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Add Image'),
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

class _SourceItemRow extends ConsumerStatefulWidget {
  final _FlatSourceNode flatNode;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final TexturePackerNotifier notifier;

  const _SourceItemRow({
    super.key,
    required this.flatNode,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.notifier,
  });

  @override
  ConsumerState<_SourceItemRow> createState() => _SourceItemRowState();
}

class _SourceItemRowState extends ConsumerState<_SourceItemRow> {
  _SourceDropPos? _dropPosition;

  bool get _isContainer => widget.flatNode.node.type == SourceNodeType.folder;

  @override
  Widget build(BuildContext context) {
    final node = widget.flatNode.node;
    final activeId = ref.watch(activeSourceImageIdProvider);
    final isSelected = node.id == activeId;
    final theme = Theme.of(context);

    Widget content = Container(
      height: 32,
      padding: EdgeInsets.only(left: widget.flatNode.depth * 16.0 + 8.0),
      color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.3) : null,
      child: Row(
        children: [
          if (_isContainer)
            GestureDetector(
              onTap: widget.onToggleExpand,
              child: Icon(widget.isExpanded ? Icons.arrow_drop_down : Icons.arrow_right, size: 20),
            )
          else
            const SizedBox(width: 20),
          
          Icon(
            _isContainer ? (widget.isExpanded ? Icons.folder_open : Icons.folder) : Icons.image_outlined,
            size: 18,
            color: _isContainer ? Colors.yellow[700] : null,
          ),
          const SizedBox(width: 8),
          
          Expanded(
            child: Text(
              node.name,
              maxLines: 1, 
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          _buildContextMenu(),
        ],
      ),
    );

    if (_dropPosition != null) {
      content = CustomPaint(
        foregroundPainter: _SourceDropPainter(position: _dropPosition!, color: theme.colorScheme.primary),
        child: content,
      );
    }

    final draggable = LongPressDraggable<String>(
      data: node.id,
      feedback: Material(
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.all(8),
          color: theme.cardColor,
          child: Row(children: [const Icon(Icons.photo_library), const SizedBox(width: 8), Text(node.name)]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: content),
      child: content,
    );

    return DragTarget<String>(
      onWillAccept: (draggedId) {
        if (draggedId == null || draggedId == node.id) return false;
        return true;
      },
      onMove: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localPos = box.globalToLocal(details.offset);
        final h = box.size.height;

        _SourceDropPos newPos;
        if (localPos.dy < h * 0.25) {
          newPos = _SourceDropPos.above;
        } else if (localPos.dy > h * 0.75) {
          newPos = _SourceDropPos.below;
        } else {
          newPos = _isContainer ? _SourceDropPos.inside : _SourceDropPos.below;
        }
        if (_dropPosition != newPos) setState(() => _dropPosition = newPos);
      },
      onLeave: (_) => setState(() => _dropPosition = null),
      onAccept: (draggedId) {
        if (_dropPosition == null) return;
        final pId = widget.flatNode.parentId;
        final idx = widget.flatNode.indexInParent;

        switch (_dropPosition!) {
          case _SourceDropPos.above:
            widget.notifier.moveSourceNode(draggedId, pId, idx);
            break;
          case _SourceDropPos.below:
            widget.notifier.moveSourceNode(draggedId, pId, idx + 1);
            break;
          case _SourceDropPos.inside:
            widget.notifier.moveSourceNode(draggedId, node.id, 0);
            if (!widget.isExpanded) widget.onToggleExpand();
            break;
        }
        setState(() => _dropPosition = null);
      },
      builder: (ctx, cand, rej) {
        return InkWell(
          onTap: () {
            if (!_isContainer) ref.read(activeSourceImageIdProvider.notifier).state = node.id;
          },
          child: draggable,
        );
      },
    );
  }

  Widget _buildContextMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16),
      onSelected: (val) async {
        if (val == 'delete') {
          final confirm = await showConfirmDialog(context, title: 'Remove?', content: 'Links will be broken.');
          if (confirm) widget.notifier.removeSourceNode(widget.flatNode.node.id);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'delete', child: Text('Remove', style: TextStyle(color: Colors.red))),
      ],
    );
  }
}

class _SourceRootDropZone extends StatefulWidget {
  final TexturePackerNotifier notifier;
  final SourceImageNode rootNode;
  const _SourceRootDropZone({required this.notifier, required this.rootNode});
  @override
  State<_SourceRootDropZone> createState() => _SourceRootDropZoneState();
}

class _SourceRootDropZoneState extends State<_SourceRootDropZone> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (d) => d != null,
      onEnter: (_) => setState(() => _hover = true),
      onLeave: (_) => setState(() => _hover = false),
      onAccept: (id) {
        setState(() => _hover = false);
        widget.notifier.moveSourceNode(id, 'root', widget.rootNode.children.length);
      },
      builder: (ctx, cand, rej) => Container(
        height: 80,
        color: _hover ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
        alignment: Alignment.center,
        child: _hover ? const Text("Move to Root") : null,
      ),
    );
  }
}

class _SourceDropPainter extends CustomPainter {
  final _SourceDropPos position;
  final Color color;
  _SourceDropPainter({required this.position, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    if (position == _SourceDropPos.above) canvas.drawLine(Offset(0,1), Offset(size.width,1), p);
    else if (position == _SourceDropPos.below) canvas.drawLine(Offset(0,size.height-1), Offset(size.width,size.height-1), p);
    else canvas.drawRect(Rect.fromLTWH(1,1,size.width-2,size.height-2), p);
  }
  @override
  bool shouldRepaint(_SourceDropPainter old) => old.position != position || old.color != color;
}