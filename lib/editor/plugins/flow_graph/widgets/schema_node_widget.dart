// FILE: lib/editor/plugins/flow_graph/widgets/schema_node_widget.dart

import 'package:flutter/material.dart';
import '../flow_graph_notifier.dart';
import '../models/flow_graph_models.dart';
import '../models/flow_schema_models.dart';
import '../models/flow_references.dart';
import 'property_tiled_object_picker.dart';

class SchemaNodeWidget extends StatelessWidget {
  final FlowNode node;
  final FlowNodeType? schema; // Null if unknown node
  final bool isSelected;
  final FlowGraphNotifier notifier;

  const SchemaNodeWidget({
    super.key,
    required this.node,
    required this.schema,
    required this.isSelected,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    // If schema is missing, show a red error node
    if (schema == null) {
      return _buildErrorNode();
    }

    return GestureDetector(
      onPanUpdate: (details) {
        notifier.moveNode(node.id, node.position + details.delta);
      },
      onTap: () {
        notifier.selectNode(node.id);
      },
      child: Container(
        width: 150, // Fixed width for layout simplicity
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.black,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _getCategoryColor(schema!.category),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                schema!.label,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            
            const SizedBox(height: 4),

            // Ports Area
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Inputs
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: schema!.inputs.map((p) => _buildPort(p, isInput: true)).toList(),
                  ),
                ),
                // Outputs
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: schema!.outputs.map((p) => _buildPort(p, isInput: false)).toList(),
                  ),
                ),
              ],
            ),

            // Properties Area
            if (schema!.properties.isNotEmpty)
              const Divider(color: Colors.grey, height: 12),
            
            ...schema!.properties.map((prop) => _buildPropertyField(prop)),
            
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPort(FlowPortDefinition port, {required bool isInput}) {
    return GestureDetector(
      onPanStart: (_) => notifier.startConnectionDrag(node.id, port.key, isInput),
      onPanUpdate: (d) => notifier.updateConnectionDrag(d.globalPosition, Matrix4.identity()), // Pass real transform in prod
      onPanEnd: (_) => notifier.endConnectionDrag(null, null), // Handle drop target logic via DragTarget usually
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: isInput ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: [
            if (isInput) _buildPortCircle(port),
            if (isInput) const SizedBox(width: 6),
            Text(
              port.label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            if (!isInput) const SizedBox(width: 6),
            if (!isInput) _buildPortCircle(port),
          ],
        ),
      ),
    );
  }

  Widget _buildPortCircle(FlowPortDefinition port) {
    Color color = port.customColor ?? Colors.grey;
    if (port.type == FlowPortType.execution) color = Colors.white;
if (port.type == FlowPortType.string) color = Colors.pink;
    if (port.type == FlowPortType.number) color = Colors.cyan;
    // Use DragTarget to accept connections
    return DragTarget<String>(
      builder: (context, candidate, rejected) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 1),
          ),
        );
      },
      onWillAccept: (_) {
        // Logic to check type compatibility
        return true;
      },
      onAccept: (_) {
        notifier.endConnectionDrag(node.id, port.key);
      },
    );
  }

  Widget _buildPropertyField(FlowPropertyDefinition prop) {
    // Basic read-only or simple edit for now
    final val = node.properties[prop.key] ?? prop.defaultValue;
    if (prop.type == FlowPropertyType.tiledObjectRef) {
      final refValue = TiledObjectReference.fromDynamic(val);
      return PropertyTiledObjectPicker(
        definition: prop,
        value: refValue,
        onChanged: (newRef) {
          // Store complex object, will be serialized to JSON automatically via toJson()
          notifier.updateNodeProperty(node.id, prop.key, newRef);
        },
      );
    }    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Text("${prop.label}: ", style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Expanded(
            child: Text(
              "$val", 
              style: const TextStyle(fontSize: 11, color: Colors.white), 
              overflow: TextOverflow.ellipsis
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorNode() {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: Column(
        children: [
          Text("Unknown: ${node.type}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          const Text("Missing schema", style: TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'logic': return Colors.blue.shade700;
      case 'math': return Colors.teal.shade700;
      case 'events': return Colors.red.shade700;
      case 'tiled': return Colors.green.shade700;
      default: return Colors.grey.shade700;
    }
  }
}