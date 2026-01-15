// lib/editor/plugins/tiled_editor/widgets/layers_panel.dart

import 'package:flutter/material.dart';
import 'package:tiled/tiled.dart' hide Text;

// Used to identify what is being dragged
class _LayerPanelDragData {
  final String type; // 'layer' or 'object'
  final int id; // layerId or objectId
  final int index; // Original index in the list/collection
  final int? parentLayerId; // only for objects

  _LayerPanelDragData.layer(this.id, this.index)
      : type = 'layer',
        parentLayerId = null;
  _LayerPanelDragData.object(this.id, this.index, this.parentLayerId)
      : type = 'object';
}

enum _DropPosition { above, below, inside }

class LayersPanel extends StatefulWidget {
  final List<Layer> layers;
  final int selectedLayerId;
  final List<TiledObject> selectedObjects;
  
  final ValueChanged<int> onLayerSelected;
  final ValueChanged<TiledObject> onObjectSelected;
  
  final ValueChanged<int> onLayerVisibilityChanged;
  final void Function(int layerId, int objectId) onObjectVisibilityChanged;
  
  final void Function(int oldIndex, int newIndex) onLayerReorder;
  final void Function(int layerId, int oldIndex, int newIndex) onObjectReorder;
  
  final VoidCallback onAddLayer;
  
  final ValueSetter<int> onLayerDelete;
  final void Function(int layerId, int objectId) onObjectDelete;
  
  final ValueSetter<Layer> onLayerInspect;
  final ValueSetter<TiledObject> onObjectInspect;

  const LayersPanel({
    super.key,
    required this.layers,
    required this.selectedLayerId,
    required this.selectedObjects,
    required this.onLayerSelected,
    required this.onObjectSelected,
    required this.onLayerVisibilityChanged,
    required this.onObjectVisibilityChanged,
    required this.onLayerReorder,
    required this.onObjectReorder,
    required this.onAddLayer,
    required this.onLayerDelete,
    required this.onObjectDelete,
    required this.onLayerInspect,
    required this.onObjectInspect,
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

  List<_FlatNode> _buildFlatList() {
    final List<_FlatNode> flatList = [];

    for (int i = widget.layers.length - 1; i >= 0; i--) {
      final layer = widget.layers[i];
      flatList.add(_FlatNode.layer(
        layer: layer,
        index: i,
        depth: 0,
      ));

      if (layer is ObjectGroup && _expandedLayerIds.contains(layer.id)) {
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
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Hierarchy',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: flatList.length,
              itemBuilder: (context, index) {
                final node = flatList[index];
                return _HierarchyRow(
                  node: node,
                  isSelectedLayer:
                      node.layer?.id == widget.selectedLayerId,
                  isObjectSelected: node.isObject
                      ? widget.selectedObjects.contains(node.object)
                      : false,
                  isExpanded: node.isLayer
                      ? _expandedLayerIds.contains(node.layer!.id)
                      : false,
                  onToggleExpand: () =>
                      _toggleExpansion(node.layer!.id!),
                  onTap: () {
                    if (node.isLayer) {
                      widget.onLayerSelected(node.layer!.id!);
                    } else {
                      widget.onLayerSelected(node.parentLayerId!);
                      widget.onObjectSelected(node.object!);
                    }
                  },
                  onVisibilityToggle: () {
                    if (node.isLayer) {
                      widget.onLayerVisibilityChanged(node.layer!.id!);
                    } else {
                      widget.onObjectVisibilityChanged(node.parentLayerId!, node.object!.id);
                    }
                  },
                  onInspect: () {
                    if (node.isLayer) {
                      widget.onLayerInspect(node.layer!);
                    } else {
                      widget.onObjectInspect(node.object!);
                    }
                  },
                  onDelete: () {
                    if (node.isLayer) {
                      widget.onLayerDelete(node.layer!.id!);
                    } else {
                      widget.onObjectDelete(node.parentLayerId!, node.object!.id);
                    }
                  },
                  onReorderLayer: widget.onLayerReorder,
                  onReorderObject: widget.onObjectReorder,
                );
              },
            ),
          ),
          const Divider(height: 1),
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
  final int index;
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

    bool isVisible = false;
    if (widget.node.isLayer) {
      isVisible = widget.node.layer?.visible ?? true;
    } else {
      isVisible = widget.node.object?.visible ?? true;
    }

    Widget content = Container(
      height: 32,
      padding: EdgeInsets.only(left: widget.node.depth * 16.0 + 4.0),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withOpacity(0.3)
          : null,
      child: Row(
        children: [
          // Expander for ObjectGroups
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
                fontStyle:
                    (widget.node.isLayer && widget.node.layer is! TileLayer)
                        ? FontStyle.italic
                        : FontStyle.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Actions
          IconButton(
            icon: Icon(
              isVisible ? Icons.visibility : Icons.visibility_off,
              size: 16,
              color: theme.disabledColor,
            ),
            onPressed: widget.onVisibilityToggle,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: widget.onInspect,
          ),
          // Only show delete for objects here to save space, or for layers too if desired.
          // Let's show for both but smaller.
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            onPressed: widget.onDelete,
          ),
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
          ? _LayerPanelDragData.layer(
              widget.node.layer!.id!, widget.node.index)
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

    return DragTarget<_LayerPanelDragData>(
      onWillAccept: (data) {
        if (data == null) return false;
        if (data.type == 'layer' && widget.node.isLayer) {
          return data.id != widget.node.layer!.id;
        }
        if (data.type == 'object' && widget.node.isObject) {
          return data.parentLayerId == widget.node.parentLayerId &&
              data.id != widget.node.object!.id;
        }
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
          if (_dropPosition == _DropPosition.above) {
            targetIndex += 1;
          }
          widget.onReorderLayer(data.index, targetIndex);

        } else if (data.type == 'object' && widget.node.isObject) {
          int targetIndex = widget.node.index;
          if (_dropPosition == _DropPosition.below) {
            targetIndex += 1;
          }
          widget.onReorderObject(data.parentLayerId!, data.index, targetIndex);
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
      if (l is ImageLayer) return Icons.image_outlined;
      return Icons.layers;
    } else {
      final o = widget.node.object!;
      if (o.isPoint) return Icons.add_location_alt_outlined;
      if (o.isEllipse) return Icons.circle_outlined;
      if (o.isPolygon) return Icons.pentagon_outlined;
      if (o.isPolyline) return Icons.polyline_outlined;
      if (o.text != null) return Icons.text_fields_outlined;
      if (o.gid != null) return Icons.image_aspect_ratio_outlined;
      return Icons.rectangle_outlined;
    }
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
      canvas.drawLine(
          Offset(0, size.height - 1), Offset(size.width, size.height - 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DropIndicatorPainter old) =>
      old.position != position || old.color != color;
}