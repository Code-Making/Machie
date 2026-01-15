import 'package:flutter/material.dart';
import 'package:tiled/tiled.dart' hide Text;

// Used to identify what is being dragged
class _LayerPanelDragData {
  final String type;
  final int id;
  final int index; // Added this
  final int? parentLayerId;

  _LayerPanelDragData.layer(this.id, this.index)
      : type = 'layer',
        parentLayerId = null;
  _LayerPanelDragData.object(this.id, this.index, this.parentLayerId) : type = 'object';
}

enum _DropPosition { above, below, inside }

class LayersPanel extends StatefulWidget {
  final List<Layer> layers;
  final int selectedLayerId;
  final List<TiledObject> selectedObjects;
  final ValueChanged<int> onLayerSelected;
  final ValueChanged<TiledObject> onObjectSelected;
  final ValueChanged<int> onVisibilityChanged;
  final void Function(int oldIndex, int newIndex) onLayerReorder;
  final void Function(int layerId, int oldIndex, int newIndex) onObjectReorder;
  final VoidCallback onAddLayer;
  final ValueSetter<int> onLayerDelete;
  final ValueSetter<Layer> onLayerInspect;

  const LayersPanel({
    super.key,
    required this.layers,
    required this.selectedLayerId,
    required this.selectedObjects,
    required this.onLayerSelected,
    required this.onObjectSelected,
    required this.onVisibilityChanged,
    required this.onLayerReorder,
    required this.onObjectReorder,
    required this.onAddLayer,
    required this.onLayerDelete,
    required this.onLayerInspect,
  });

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends State<LayersPanel> {
  final Set<int> _expandedLayerIds = {};

  void _toggleExpansion(int layerId) {
    setState(() {
      if (_expandedLayerIds.contains(layerId)) {
        _expandedLayerIds.remove(layerId);
      } else {
        _expandedLayerIds.add(layerId);
      }
    });
  }

  // Flatten the tree for ListView
  List<_FlatNode> _buildFlatList() {
    final List<_FlatNode> flatList = [];
    
    // Iterate reversed so top layer in list = top layer visually (draw order)
    // Tiled layers[0] is bottom-most.
    for (int i = widget.layers.length - 1; i >= 0; i--) {
      final layer = widget.layers[i];
      flatList.add(_FlatNode.layer(
        layer: layer,
        index: i,
        depth: 0,
      ));

      if (layer is ObjectGroup && _expandedLayerIds.contains(layer.id)) {
        // Objects: standard order usually matches index order
        for (int j = 0; j < layer.objects.length; j++) {
          flatList.add(_FlatNode.object(
            object: layer.objects[j],
            parentLayerId: layer.id!,
            index: j,
            depth: 1,
          ));
        }
      }
    }
    return flatList;
  }

  @override
  Widget build(BuildContext context) {
    final flatList = _buildFlatList();

    return Material(
      elevation: 4,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Hierarchy',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(height: 1),
          
          // Tree List
          Expanded(
            child: ListView.builder(
              itemCount: flatList.length,
              itemBuilder: (context, index) {
                return _HierarchyRow(
                  node: flatList[index],
                  isSelectedLayer:
                      flatList[index].layer?.id == widget.selectedLayerId,
                  isObjectSelected: flatList[index].isObject
                      ? widget.selectedObjects
                          .contains(flatList[index].object)
                      : false,
                  isExpanded: flatList[index].isLayer
                      ? _expandedLayerIds
                          .contains(flatList[index].layer!.id)
                      : false,
                  onToggleExpand: () =>
                      _toggleExpansion(flatList[index].layer!.id!),
                  onTap: () {
                    final node = flatList[index];
                    if (node.isLayer) {
                      widget.onLayerSelected(node.layer!.id!);
                    } else {
                      widget.onLayerSelected(node.parentLayerId!);
                      widget.onObjectSelected(node.object!);
                    }
                  },
                  onVisibilityToggle: () {
                    final node = flatList[index];
                    if (node.isLayer) {
                      widget.onVisibilityChanged(node.layer!.id!);
                    } else {
                      // Object visibility toggle logic (if supported by notifier)
                      // For now, objects inherit layer, but TiledObject has visible property too
                      // This would need a specific callback in TiledMapNotifier like toggleObjectVisibility
                    }
                  },
                  onInspect: () {
                     final node = flatList[index];
                     if(node.isLayer) {
                       widget.onLayerInspect(node.layer!);
                     }
                  },
                  onDelete: () {
                    final node = flatList[index];
                    if(node.isLayer) {
                      widget.onLayerDelete(node.layer!.id!);
                    }
                  },
                  onReorderLayer: widget.onLayerReorder,
                  onReorderObject: widget.onObjectReorder,
                );
              },
            ),
          ),
          const Divider(height: 1),
          // Footer Actions
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Layer'),
              onPressed: widget.onAddLayer,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlatNode {
  final Layer? layer;
  final TiledObject? object;
  final int index; // Index in the source list
  final int depth;
  final int? parentLayerId;

  _FlatNode.layer({
    required this.layer,
    required this.index,
    required this.depth,
  })  : object = null,
        parentLayerId = null;

  _FlatNode.object({
    required this.object,
    required this.parentLayerId,
    required this.index,
    required this.depth,
  }) : layer = null;

  bool get isLayer => layer != null;
  bool get isObject => object != null;
  int get id => isLayer ? layer!.id! : object!.id;
}

class _HierarchyRow extends StatefulWidget {
  final _FlatNode node;
  final bool isSelectedLayer;
  final bool isObjectSelected;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onTap;
  final VoidCallback onVisibilityToggle;
  final VoidCallback onInspect;
  final VoidCallback onDelete;
  final Function(int, int) onReorderLayer;
  final Function(int, int, int) onReorderObject;

  const _HierarchyRow({
    required this.node,
    required this.isSelectedLayer,
    required this.isObjectSelected,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onTap,
    required this.onVisibilityToggle,
    required this.onInspect,
    required this.onDelete,
    required this.onReorderLayer,
    required this.onReorderObject,
  });

  @override
  State<_HierarchyRow> createState() => _HierarchyRowState();
}

class _HierarchyRowState extends State<_HierarchyRow> {
  _DropPosition? _dropPosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = widget.node.isLayer
        ? widget.isSelectedLayer
        : widget.isObjectSelected;

    Widget content = Container(
      height: 32,
      padding: EdgeInsets.only(left: widget.node.depth * 16.0 + 4.0),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withOpacity(0.3)
          : null,
      child: Row(
        children: [
          // Expander
          if (widget.node.isLayer && widget.node.layer is ObjectGroup)
            GestureDetector(
              onTap: widget.onToggleExpand,
              child: Icon(
                widget.isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                size: 20,
              ),
            )
          else
            const SizedBox(width: 20),

          // Icon
          Icon(_getIcon(), size: 16),
          const SizedBox(width: 8),

          // Name
          Expanded(
            child: Text(
              _getName(),
              style: TextStyle(
                color: isSelected ? theme.colorScheme.primary : null,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                fontStyle: (widget.node.isLayer && widget.node.layer is! TileLayer)
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Actions
          if(widget.node.isLayer) ...[
             IconButton(
              icon: Icon(
                (widget.node.layer?.visible ?? true)
                    ? Icons.visibility
                    : Icons.visibility_off,
                size: 16,
                color: theme.disabledColor,
              ),
              onPressed: widget.onVisibilityToggle,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              onPressed: widget.onInspect,
            ),
          ] else if (widget.node.isObject) ...[
             // For objects, show small indicator or type?
             // Keeping it simple for now to avoid clutter
          ]
        ],
      ),
    );

    // Drop Indicator Painter
    if (_dropPosition != null) {
      content = CustomPaint(
        foregroundPainter: _DropIndicatorPainter(
          position: _dropPosition!,
          color: theme.colorScheme.primary,
        ),
        child: content,
      );
    }

    // Draggable
final draggable = LongPressDraggable<_LayerPanelDragData>(
      data: widget.node.isLayer
          ? _LayerPanelDragData.layer(widget.node.layer!.id!, widget.node.index)
          : _LayerPanelDragData.object(
              widget.node.object!.id, widget.node.index, widget.node.parentLayerId!),
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
              Text(_getName()),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: content),
      child: content,
    );

    // Drag Target
    return DragTarget<_LayerPanelDragData>(
      onWillAccept: (data) {
        if (data == null) return false;
        // Layer dragged onto Layer
        if (data.type == 'layer' && widget.node.isLayer) {
          return data.id != widget.node.layer!.id; // Don't drop on self
        }
        // Object dragged onto Object
        if (data.type == 'object' && widget.node.isObject) {
          // Only allow reordering within same layer for now
          return data.parentLayerId == widget.node.parentLayerId &&
              data.id != widget.node.object!.id;
        }
        // Object dragged onto its own Layer (reparenting logic or simple drop to top?)
        // For simplicity in Phase 1: Only Object <-> Object reordering
        return false;
      },
      onMove: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final localPos = renderBox.globalToLocal(details.offset);
        final height = renderBox.size.height;

        _DropPosition newPos;
        if (localPos.dy < height * 0.5) {
          newPos = _DropPosition.above;
        } else {
          newPos = _DropPosition.below;
        }

        if (_dropPosition != newPos) {
          setState(() => _dropPosition = newPos);
        }
      },
      onLeave: (_) => setState(() => _dropPosition = null),
onAccept: (data) {
        setState(() => _dropPosition = null);
        if (data.type == 'layer' && widget.node.isLayer) {
          int targetIndex = widget.node.index; 
          // visual top = list end. 
          // dropping "above" (visually) -> higher index
          if (_dropPosition == _DropPosition.above) {
             targetIndex += 1;
          }
          widget.onLayerReorder(data.index, targetIndex);

        } else if (data.type == 'object' && widget.node.isObject) {
          int targetIndex = widget.node.index;
          // visual top = list start (0).
          // dropping "above" (visually) -> lower index
          // But here we rendered objects in index order (0 to N).
          // So "above" means index, "below" means index + 1.
          if (_dropPosition == _DropPosition.below) {
            targetIndex += 1;
          }
          widget.onObjectReorder(data.parentLayerId!, data.index, targetIndex);
        }
      },
      builder: (ctx, _, __) => InkWell(
        onTap: widget.onTap,
        child: draggable,
      ),
    );
  }

  String _getName() {
    if (widget.node.isLayer) return widget.node.layer!.name;
    final obj = widget.node.object!;
    return obj.name.isNotEmpty ? obj.name : 'Object ${obj.id}';
  }

  IconData _getIcon() {
    if (widget.node.isLayer) {
      final l = widget.node.layer!;
      if (l is TileLayer) return Icons.grid_on;
      if (l is ObjectGroup) {
        return widget.isExpanded ? Icons.folder_open : Icons.folder;
      }
      if (l is ImageLayer) return Icons.image;
      return Icons.layers;
    } else {
      final o = widget.node.object!;
      if (o.isPoint) return Icons.add_location;
      if (o.isEllipse) return Icons.circle_outlined;
      if (o.isPolygon) return Icons.pentagon_outlined;
      if (o.isPolyline) return Icons.polyline;
      if (o.text != null) return Icons.text_fields;
      if (o.gid != null) return Icons.image_aspect_ratio; // Tile object
      return Icons.rectangle_outlined;
    }
  }

  // Helper to find original index because drag data only has ID
  int _findLayerIndexById(int id) {
    // Access ancestor to find index? Or simple hack:
    // In production, better to pass source index in DragData if list doesn't mutate during drag
    // But DragData is created at start. 
    // This requires the parent Widget to pass down a lookup or handle the index translation.
    // For Phase 1, we rely on the parent logic or assume data passed is correct.
    // Actually, TiledMapNotifier expects generic indices. 
    // Let's assume the controller can handle ID lookup, OR we assume we can't easily find it here 
    // without context.
    // FIX: DragData should contain the original index at drag start.
    // But if we scroll, it's fine.
    // Let's update `_LayerPanelDragData`? No, simpler to find it via the ancestor.
    // For brevity in this snippet, I will assume `widget.onLayerReorder` handles index resolution 
    // OR we pass indices in drag data.
    // Let's assume we pass indices in DragData for simplicity in Phase 1 (see below update).
    return 0; // Placeholder, see logic update in Step 2b
  }
  
  int _findObjectIndex(int layerId, int objectId) {
    // Same logic.
    return 0; // Placeholder
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

    if (position == _DropPosition.above) {
      canvas.drawLine(Offset(0, 1), Offset(size.width, 1), paint);
    } else if (position == _DropPosition.below) {
      canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DropIndicatorPainter old) =>
      old.position != position || old.color != color;
}