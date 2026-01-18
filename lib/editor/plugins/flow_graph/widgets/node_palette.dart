// FILE: lib/editor/plugins/flow_graph/widgets/node_palette.dart

import 'package:flutter/material.dart';
import '../asset/flow_asset_models.dart';
import '../models/flow_schema_models.dart';

class NodePalette extends StatefulWidget {
  final FlowSchemaAssetData schema;
  final ValueChanged<FlowNodeType> onNodeSelected;
  final VoidCallback onClose;

  const NodePalette({
    super.key,
    required this.schema,
    required this.onNodeSelected,
    required this.onClose,
  });

  @override
  State<NodePalette> createState() => _NodePaletteState();
}

class _NodePaletteState extends State<NodePalette> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Filter and Group nodes
    final filtered = widget.schema.nodeTypes.where((n) {
      return n.label.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             n.category.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final grouped = <String, List<FlowNodeType>>{};
    for (var node in filtered) {
      grouped.putIfAbsent(node.category, () => []).add(node);
    }

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text("Add Node", style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: widget.onClose),
              ],
            ),
          ),
          
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: "Search...",
                prefixIcon: Icon(Icons.search, size: 16),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(height: 8),

          // List
          Expanded(
            child: ListView.builder(
              itemCount: grouped.keys.length,
              itemBuilder: (context, index) {
                final category = grouped.keys.elementAt(index);
                final nodes = grouped[category]!;
                
                return ExpansionTile(
                  title: Text(category, style: const TextStyle(fontSize: 14)),
                  initiallyExpanded: true,
                  children: nodes.map((node) {
                    return ListTile(
                      dense: true,
                      title: Text(node.label),
                      subtitle: node.description.isNotEmpty 
                          ? Text(node.description, maxLines: 1, overflow: TextOverflow.ellipsis) 
                          : null,
                      onTap: () => widget.onNodeSelected(node),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}