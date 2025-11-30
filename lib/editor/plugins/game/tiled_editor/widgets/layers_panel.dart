// lib/editor/plugins/tiled_editor/widgets/layers_panel.dart

import 'package:flutter/material.dart';

import 'package:tiled/tiled.dart' hide Text;

class LayersPanel extends StatelessWidget {
  final List<Layer> layers;
  final int selectedLayerId;
  final ValueChanged<int> onLayerSelected;
  final ValueChanged<int> onVisibilityChanged;
  final void Function(int oldIndex, int newIndex) onLayerReorder;
  final VoidCallback onAddLayer;
  final ValueSetter<int> onLayerDelete;
  final ValueSetter<Layer> onLayerInspect;

  const LayersPanel({
    super.key,
    required this.layers,
    required this.selectedLayerId,
    required this.onLayerSelected,
    required this.onVisibilityChanged,
    required this.onLayerReorder,
    required this.onAddLayer,
    required this.onLayerDelete,
    required this.onLayerInspect,
  });
  IconData _getIconForLayer(Layer layer) {
    if (layer is TileLayer) return Icons.grid_on;
    if (layer is ObjectGroup) return Icons.category_outlined;
    if (layer is ImageLayer) return Icons.image_outlined;
    if (layer is Group) return Icons.folder_copy_outlined;
    return Icons.layers;
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = layers.length;

    return Material(
      elevation: 4,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(8),
      ),
      child: Container(
        padding: const EdgeInsets.all(8.0),
        constraints: const BoxConstraints(maxHeight: 250, minHeight: 150),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Layers',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const Divider(),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: itemCount,
                onReorder: (oldVisualIndex, newVisualIndex) {
                  // The data model is stored in the reverse order of the UI list.
                  // UI index 0 is data index (itemCount - 1).

                  // First, we must apply the standard adjustment to the VISUAL newIndex.
                  // This is because when moving an item down the list, the list effectively
                  // shrinks, and the ReorderableListView reports an index that is one higher
                  // than the final insertion point.
                  if (oldVisualIndex < newVisualIndex) {
                    newVisualIndex -= 1;
                  }

                  // Now, with the corrected visual indices, convert them to data model indices.
                  final int oldDataIndex = itemCount - 1 - oldVisualIndex;
                  final int newDataIndex = itemCount - 1 - newVisualIndex;

                  // Pass the final, correct data indices to the callback.
                  onLayerReorder(oldDataIndex, newDataIndex);
                },
                itemBuilder: (context, index) {
                  final int dataIndex = itemCount - 1 - index;
                  final layer = layers[dataIndex];
                  final isPaintable = layer is TileLayer;

                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(layer.id),
                    index: index,
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 0, right: 8),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<int>(
                            value: layer.id!,
                            groupValue: selectedLayerId,
                            onChanged: (value) => onLayerSelected(value!),
                          ),
                          Icon(_getIconForLayer(layer), size: 20),
                        ],
                      ),
                      title: Text(
                        layer.name,
                        style: TextStyle(
                          fontStyle:
                              isPaintable ? FontStyle.normal : FontStyle.italic,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Layer Properties',
                            onPressed: () => onLayerInspect(layer),
                          ),
                          IconButton(
                            icon: Icon(
                              layer.visible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            tooltip: 'Toggle Visibility',
                            onPressed: () => onVisibilityChanged(layer.id!),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.redAccent,
                            ),
                            tooltip: 'Delete Layer',
                            onPressed:
                                layers.length > 1
                                    ? () => onLayerDelete(layer.id!)
                                    : null,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Layer'),
              onPressed: onAddLayer,
            ),
          ],
        ),
      ),
    );
  }
}
