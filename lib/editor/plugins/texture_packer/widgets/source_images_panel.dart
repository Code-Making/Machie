import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart';

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
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    final root = widget.notifier.project.sourceImagesRoot;
    for (final child in root.children) {
      if (child.type == SourceNodeType.folder) {
        _expandedIds.add(child.id);
      }
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

  List<Widget> _buildFlatList(SourceImageNode root) {
    final List<Widget> widgets = [];

    void traverse(SourceImageNode parent, int depth) {
      final children = parent.children;
      final double indent = depth * 16.0;

      if (children.isEmpty && parent.id != 'root') {
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent),
          child: _EmptySourceDropZone(
            parentId: parent.id, 
            notifier: widget.notifier
          ),
        ));
        return;
      }

      for (int i = 0; i < children.length; i++) {
        final child = children[i];
        
        widgets.add(_SourceReorderDropZone(
          parentId: parent.id, 
          index: i, 
          notifier: widget.notifier,
          indent: indent,
        ));

        final isFolder = child.type == SourceNodeType.folder;
        final isExpanded = _expandedIds.contains(child.id);

        widgets.add(_SourceTreeItem(
          node: child,
          notifier: widget.notifier,
          depth: depth,
          isExpanded: isExpanded,
          onToggleExpand: () => _toggleExpansion(child.id),
        ));

        if (isFolder && isExpanded) {
          traverse(child, depth + 1);
        }
      }

      if (children.isNotEmpty) {
        widgets.add(_SourceReorderDropZone(
          parentId: parent.id, 
          index: children.length, 
          notifier: widget.notifier,
          indent: indent,
        ));
      }
    }

    traverse(root, 0);
    
    widgets.add(const SizedBox(height: 16));
    widgets.add(_SourceRootDropZone(notifier: widget.notifier, rootNode: root));
    widgets.add(const SizedBox(height: 32));

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final rootNode = widget.notifier.project.sourceImagesRoot;
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
                Text('Source Images', style: Theme.of(context).textTheme.titleMedium),
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

          // List
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

class _SourceRootDropZone extends StatefulWidget {
  final TexturePackerNotifier notifier;
  final SourceImageNode rootNode;

  const _SourceRootDropZone({required this.notifier, required this.rootNode});

  @override
  State<_SourceRootDropZone> createState() => _SourceRootDropZoneState();
}

class _SourceRootDropZoneState extends State<_SourceRootDropZone> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (draggedId) {
        if (draggedId == null) return false;
        if (widget.rootNode.children.any((c) => c.id == draggedId)) return false;
        setState(() => _isHovered = true);
        return true;
      },
      onLeave: (_) => setState(() => _isHovered = false),
      onAccept: (draggedId) {
        setState(() => _isHovered = false);
        widget.notifier.moveSourceNode(draggedId, 'root', widget.rootNode.children.length);
      },
      builder: (context, candidates, rejected) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          height: 50,
          decoration: BoxDecoration(
            color: _isHovered ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
            border: _isHovered ? Border.all(color: Theme.of(context).colorScheme.primary) : null,
            borderRadius: BorderRadius.circular(4),
          ),
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

class _SourceTreeItem extends ConsumerStatefulWidget {
  final SourceImageNode node;
  final TexturePackerNotifier notifier;
  final int depth;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const _SourceTreeItem({
    required this.node,
    required this.notifier,
    required this.depth,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  ConsumerState<_SourceTreeItem> createState() => _SourceTreeItemState();
}

class _SourceTreeItemState extends ConsumerState<_SourceTreeItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isFolder = node.type == SourceNodeType.folder;

    Widget content = _buildTile(context, ref);

    if (isFolder) {
      content = DragTarget<String>(
        onWillAccept: (draggedId) {
          if (draggedId == null || draggedId == node.id) return false;
          setState(() => _isHovered = true);
          return true;
        },
        onLeave: (_) => setState(() => _isHovered = false),
        onAccept: (draggedId) {
          setState(() => _isHovered = false);
          widget.notifier.moveSourceNode(draggedId, node.id, node.children.length);
          if (!widget.isExpanded) widget.onToggleExpand();
        },
        builder: (context, candidates, rejected) {
          return Container(
            decoration: BoxDecoration(
              color: _isHovered 
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.2) 
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: _isHovered 
                  ? Border.all(color: Theme.of(context).colorScheme.primary) 
                  : null,
            ),
            child: content,
          );
        },
      );
    }

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
              const Icon(Icons.photo_library),
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
    final activeId = ref.watch(activeSourceImageIdProvider);
    final isSelected = widget.node.id == activeId;
    final isFolder = widget.node.type == SourceNodeType.folder;

    return Padding(
      padding: EdgeInsets.only(left: widget.depth * 16.0),
      child: ListTile(
        leading: GestureDetector(
          onTap: isFolder ? widget.onToggleExpand : null,
          child: Icon(
            isFolder 
              ? (widget.isExpanded ? Icons.folder_open : Icons.folder)
              : Icons.image_outlined,
            size: 20,
            color: isFolder ? Colors.yellow[700] : null,
          ),
        ),
        title: Text(widget.node.name, overflow: TextOverflow.ellipsis),
        dense: true,
        selected: isSelected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        onTap: () {
          if (!isFolder) {
            ref.read(activeSourceImageIdProvider.notifier).state = widget.node.id;
          } else {
            widget.onToggleExpand();
          }
        },
        trailing: _buildContextMenu(context),
      ),
    );
  }

  Widget _buildContextMenu(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'delete') {
          final confirm = await showConfirmDialog(
            context,
            title: 'Remove "${widget.node.name}"?',
            content: 'This will remove the image/folder from the project.',
          );
          if (confirm) {
            widget.notifier.removeSourceNode(widget.node.id);
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'delete', child: Text('Remove', style: TextStyle(color: Colors.red))),
      ],
      icon: const Icon(Icons.more_vert, size: 16),
    );
  }
}

class _SourceReorderDropZone extends StatefulWidget {
  final String parentId;
  final int index;
  final TexturePackerNotifier notifier;
  final double indent;

  const _SourceReorderDropZone({
    required this.parentId,
    required this.index,
    required this.notifier,
    required this.indent,
  });

  @override
  State<_SourceReorderDropZone> createState() => _SourceReorderDropZoneState();
}

class _SourceReorderDropZoneState extends State<_SourceReorderDropZone> {
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
        widget.notifier.moveSourceNode(draggedId, widget.parentId, widget.index);
      },
      builder: (context, candidates, rejected) {
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

class _EmptySourceDropZone extends StatelessWidget {
  final String parentId;
  final TexturePackerNotifier notifier;

  const _EmptySourceDropZone({required this.parentId, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (data) => data != null,
      onAccept: (nodeId) {
        notifier.moveSourceNode(nodeId, parentId, 0);
      },
      builder: (context, candidates, rejected) {
        final isHovered = candidates.isNotEmpty;
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