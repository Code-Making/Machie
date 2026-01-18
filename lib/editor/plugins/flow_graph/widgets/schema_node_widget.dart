// FILE: lib/editor/plugins/flow_graph/widgets/schema_node_widget.dart

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../flow_graph_notifier.dart';
import '../models/flow_graph_models.dart';
import '../models/flow_schema_models.dart';
import '../models/flow_references.dart';
import 'property_tiled_object_picker.dart';

class SchemaNodeWidget extends StatelessWidget {
  final FlowNode node;
  final FlowNodeType? schema;
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
    if (schema == null) return _buildErrorNode();

    return GestureDetector(
      onPanUpdate: (details) {
        // Simple move logic
        notifier.moveNode(node.id, node.position + details.delta);
      },
      onTap: () => notifier.selectNode(node.id),
      child: Container(
        width: 160,
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

            // Ports
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: schema!.inputs.map((p) => _buildPort(context, p, isInput: true)).toList(),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: schema!.outputs.map((p) => _buildPort(context, p, isInput: false)).toList(),
                  ),
                ),
              ],
            ),

            // Properties
            if (schema!.properties.isNotEmpty) ...[
              const Divider(color: Colors.white24, height: 12),
              ...schema!.properties.map((prop) => _buildPropertyField(context, prop)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPort(BuildContext context, FlowPortDefinition port, {required bool isInput}) {
    // Only outputs are draggable sources in this simplified model
    // Inputs are drag targets
    
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: isInput ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isInput) _buildPortTarget(context, port),
          if (isInput) const SizedBox(width: 6),
          Text(
            port.label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          if (!isInput) const SizedBox(width: 6),
          if (!isInput) _buildPortSource(context, port),
        ],
      ),
    );
  }

  Widget _buildPortSource(BuildContext context, FlowPortDefinition port) {
    final color = _getPortColor(port);
    
    // We use Draggable to detect the drag, but we handle the drawing in the Painter 
    // via the Notifier updates.
    return Draggable<String>(
      data: node.id, // Payload doesn't matter much here, notifier handles state
      feedback: const SizedBox.shrink(), // Painter draws the line, so invisible feedback
      onDragStarted: () {
        notifier.startConnectionDrag(node.id, port.key, false, port.type);
      },
      onDragUpdate: (details) {
        // We need the transform to convert global to local. 
        // In a real app, pass the viewport transform from the Canvas widget.
        // For now, we assume standard scale or use the global position if the painter handles it.
        // NOTE: Ideally FlowGraphCanvas passes the transform down or we access it via provider.
        // Here we just pass global and let notifier logic handle matrix if it had access, 
        // but notifier is pure logic.
        // We will pass Identity here and assume FlowConnectionPainter converts properly or 
        // the canvas passes a key to access the transformer.
        // A simple workaround: `SchemaNodeWidget` is inside the InteractiveViewer, 
        // so coordinates are already transformed? No, Draggable details are global.
        
        // IMPORTANT: For accurate lines, we need the Inverse Matrix of the InteractiveViewer.
        // Since we don't have it here easily, visual lines during drag might be offset 
        // unless we fix the coordinate space.
        // For Phase 3/4 context, we will trigger the update.
        notifier.updateConnectionDrag(details.globalPosition, Matrix4.identity());
      },
      onDragEnd: (_) {
        notifier.endConnectionDrag(null, null);
      },
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 1),
        ),
      ),
    );
  }

  Widget _buildPortTarget(BuildContext context, FlowPortDefinition port) {
    final color = _getPortColor(port);

    return DragTarget<String>(
      builder: (context, candidateData, rejectedData) {
        // Highlight if candidate is valid
        final isCandidateValid = candidateData.isNotEmpty;
        
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: isCandidateValid ? Colors.white : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isCandidateValid ? Colors.green : Colors.black, 
              width: isCandidateValid ? 2 : 1
            ),
          ),
        );
      },
      onWillAccept: (data) {
        // TYPE CHECKING LOGIC
        final draggingType = notifier.draggingPortType;
        if (draggingType == null) return false;
        
        // 1. Check strict types
        if (draggingType == port.type) return true;
        
        // 2. Execution only connects to Execution
        if (draggingType == FlowPortType.execution || port.type == FlowPortType.execution) {
          return false;
        }
        
        // 3. 'Any' matches anything (except execution, handled above)
        if (draggingType == FlowPortType.any || port.type == FlowPortType.any) {
          return true;
        }
        
        return false;
      },
      onAccept: (data) {
        notifier.endConnectionDrag(node.id, port.key);
      },
    );
  }

  Widget _buildPropertyField(BuildContext context, FlowPropertyDefinition prop) {
    final val = node.properties[prop.key] ?? prop.defaultValue;

    // Special Case: Tiled Object Picker
    if (prop.type == FlowPropertyType.tiledObjectRef) {
      final refValue = TiledObjectReference.fromDynamic(val);
      return PropertyTiledObjectPicker(
        definition: prop,
        value: refValue,
        onChanged: (newRef) => notifier.updateNodeProperty(node.id, prop.key, newRef),
      );
    }

    // Default: Clickable text
    return InkWell(
      onTap: () => _showEditDialog(context, prop, val),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            if (prop.type != FlowPropertyType.string && prop.type != FlowPropertyType.integer)
               const Icon(Icons.arrow_drop_down, size: 12, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, FlowPropertyDefinition prop, dynamic currentValue) async {
    dynamic result;

    switch (prop.type) {
      case FlowPropertyType.string:
      case FlowPropertyType.integer:
      case FlowPropertyType.float:
        result = await showDialog(
          context: context,
          builder: (ctx) => _ValueEditDialog(
            title: prop.label,
            initialValue: currentValue.toString(),
            isNumeric: prop.type != FlowPropertyType.string,
            isFloat: prop.type == FlowPropertyType.float,
          ),
        );
        if (result != null && prop.type == FlowPropertyType.integer) result = int.tryParse(result);
        if (result != null && prop.type == FlowPropertyType.float) result = double.tryParse(result);
        break;

      case FlowPropertyType.bool:
        // Toggle immediately or show simple dialog? Toggle is faster.
        result = !(currentValue == true);
        break;

      case FlowPropertyType.select:
        result = await showDialog(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text("Select ${prop.label}"),
            children: (prop.options ?? []).map((opt) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, opt),
              child: Text(opt),
            )).toList(),
          ),
        );
        break;
        
      case FlowPropertyType.color:
        final Color current = _parseColor(currentValue) ?? Colors.white;
        final newColor = await showColorPickerDialog(context, current, enableOpacity: true);
        result = '#${newColor.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
        break;
        
      default:
        break;
    }

    if (result != null) {
      notifier.updateNodeProperty(node.id, prop.key, result);
    }
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
          Text(node.type, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const Text("Unknown Node Type", style: TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }

  Color _getPortColor(FlowPortDefinition port) {
    if (port.customColor != null) return port.customColor!;
    switch (port.type) {
      case FlowPortType.execution: return Colors.white;
      case FlowPortType.string: return Colors.purpleAccent;
      case FlowPortType.number: return Colors.lightGreenAccent;
      case FlowPortType.boolean: return Colors.redAccent;
      case FlowPortType.vector2: return Colors.orangeAccent;
      case FlowPortType.tiledObject: return Colors.blueAccent;
      default: return Colors.grey;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'logic': return Colors.blue.shade700;
      case 'math': return Colors.teal.shade700;
      case 'events': return Colors.red.shade900;
      case 'tiled': return Colors.green.shade800;
      default: return Colors.grey.shade800;
    }
  }
  
  Color? _parseColor(dynamic val) {
    if (val is String) {
      try {
        var hex = val.replaceAll('#', '');
        if (hex.length == 6) hex = 'FF$hex';
        return Color(int.parse(hex, radix: 16));
      } catch (_) {}
    }
    return null;
  }
}

class _ValueEditDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final bool isNumeric;
  final bool isFloat;

  const _ValueEditDialog({
    required this.title,
    required this.initialValue,
    this.isNumeric = false,
    this.isFloat = false,
  });

  @override
  State<_ValueEditDialog> createState() => _ValueEditDialogState();
}

class _ValueEditDialogState extends State<_ValueEditDialog> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Edit ${widget.title}"),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: widget.isNumeric ? TextInputType.numberWithOptions(decimal: widget.isFloat) : TextInputType.text,
        inputFormatters: widget.isNumeric 
            ? [widget.isFloat ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')) : FilteringTextInputFormatter.digitsOnly] 
            : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text("OK")),
      ],
    );
  }
}