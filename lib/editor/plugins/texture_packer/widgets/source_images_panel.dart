import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart';

class SourceImagesPanel extends ConsumerWidget {
  final TexturePackerNotifier notifier;
  final VoidCallback onAddImage;
  final VoidCallback onClose;

  const SourceImagesPanel({
    super.key,
    required this.notifier,
    required this.onAddImage,
    required this.onClose,
  });

  Future<void> _createFolder(BuildContext context) async {
    final name = await showTextInputDialog(context, title: 'New Folder');
    if (name != null && name.trim().isNotEmpty) {
      notifier.addSourceNode(
        name: name.trim(),
        type: SourceNodeType.folder,
        parentId: 'root',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootNode = notifier.project.sourceImagesRoot;

    return Material(
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Text('Source Images', style: Theme.of(context).textTheme.titleMedium),
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
                Positioned.fill(
                  child: _SourceRootDropZone(
                    notifier: notifier, 
                    rootNode: rootNode,
                    isBackground: true,
                  ),
                ),

                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildNodeList(rootNode, context, ref),
                      const SizedBox(height: 100), // Spacer for background drop
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
                    onPressed: () => _createFolder(context),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Folder'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAddImage,
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

  Widget _buildNodeList(SourceImageNode parent, BuildContext context, WidgetRef ref) {
    final children = parent.children;
    
    if (children.isEmpty && parent.id != 'root') {
      return Padding(
        padding: const EdgeInsets.only(left: 16.0),
        child: _EmptySourceDropZone(parentId: parent.id, notifier: notifier),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          _SourceReorderDropZone(parentId: parent.id, index: i, notifier: notifier),
          _SourceTreeItem(
            node: children[i],
            notifier: notifier,
            depth: 0,
          ),
        ],
        _SourceReorderDropZone(parentId: parent.id, index: children.length, notifier: notifier),
      ],
    );
  }
}

class _SourceRootDropZone extends StatefulWidget {
  final TexturePackerNotifier notifier;
  final SourceImageNode rootNode;
  final bool isBackground;

  const _SourceRootDropZone({
    required this.notifier, 
    required this.rootNode,
    this.isBackground = false,
  });

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

class _SourceTreeItem extends ConsumerStatefulWidget {
  final SourceImageNode node;
  final TexturePackerNotifier notifier;
  final int depth;

  const _SourceTreeItem({
    required this.node,
    required this.notifier,
    this.depth = 0,
  });

  @override
  ConsumerState<_SourceTreeItem> createState() => _SourceTreeItemState();
}

class _SourceTreeItemState extends ConsumerState<_SourceTreeItem> {
  bool _isHovered = false;
  bool _isExpanded = true;

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

    if (isFolder && _isExpanded) {
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
      return _EmptySourceDropZone(parentId: widget.node.id, notifier: widget.notifier);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          _SourceReorderDropZone(parentId: widget.node.id, index: i, notifier: widget.notifier),
          _SourceTreeItem(
            node: children[i], 
            notifier: widget.notifier,
            depth: widget.depth + 1,
          ),
        ],
        _SourceReorderDropZone(parentId: widget.node.id, index: children.length, notifier: widget.notifier),
      ],
    );
  }

  Widget _buildTile(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeSourceImageIdProvider);
    final isSelected = widget.node.id == activeId;
    final isFolder = widget.node.type == SourceNodeType.folder;

    return ListTile(
      leading: GestureDetector(
        onTap: isFolder ? () => setState(() => _isExpanded = !_isExpanded) : null,
        child: Icon(
          isFolder 
            ? (_isExpanded ? Icons.folder_open : Icons.folder)
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      onTap: () {
        if (!isFolder) {
          ref.read(activeSourceImageIdProvider.notifier).state = widget.node.id;
        }
      },
      trailing: _buildContextMenu(context),
    );
  }

  Widget _buildContextMenu(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'delete') {
          final confirm = await showConfirmDialog(
            context,
            title: 'Remove "${widget.node.name}"?',
            content: 'This will remove the image/folder from the project. References in sprites may be broken.',
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

  const _SourceReorderDropZone({required this.parentId, required this.index, required this.notifier});

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