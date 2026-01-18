// FILE: lib/editor/plugins/flow_graph/widgets/schema_node_widget.dart

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
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
  final Offset Function(Offset) globalToLocal; // NEW

  const SchemaNodeWidget({
    super.key,
    required this.node,
    required this.schema,
    required this.isSelected,
    required this.notifier,
    required this.globalToLocal,
  });

  bool _isInputConnected(String portKey) {
    return notifier.graph.connections.any(
      (c) => c.inputNodeId == node.id && c.inputPortKey == portKey
    );
  }

  @override
  Widget build(BuildContext context) {
    if (schema == null) return _buildErrorNode();

    final inputKeys = schema!.inputs.map((i) => i.key).toSet();
    final standaloneProps = schema!.properties.where((p) => !inputKeys.contains(p.key)).toList();

    return GestureDetector(
      onPanUpdate: (details) {
        // Drag node logic
        // We assume 1:1 scale for node drag here for simplicity, 
        // but InteractiveViewer scale affects details.delta.
        // For precise node moving under zoom, we should divide delta by scale.
        // We can get scale if we pass it, but standard delta often works 'okay' visually if not perfectly 1:1.
        notifier.moveNode(node.id, node.position + details.delta);
      },
      onSecondaryTapUp: (details) => _showNodeContextMenu(context, details.globalPosition),
      onTap: () => notifier.selectNode(node.id),
      child: Container(
        // Set fixed width for painter calculation consistency
        width: 200, 
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
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _getCategoryColor(schema!.category),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      schema!.label,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => notifier.deleteNode(node.id),
                    child: const Icon(Icons.close, size: 16, color: Colors.white54),
                  )
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Inputs/Outputs
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: schema!.inputs.map((input) {
                      final prop = schema!.properties.firstWhereOrNull((p) => p.key == input.key);
                      final connected = _isInputConnected(input.key);
                      return _buildInputRow(context, input, prop, connected);
                    }).toList(),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: schema!.outputs.map((output) {
                      return _buildOutputRow(context, output);
                    }).toList(),
                  ),
                ),
              ],
            ),

            // Properties
            if (standaloneProps.isNotEmpty) ...[
              const Divider(color: Colors.white12, height: 16),
              ...standaloneProps.map((prop) => _buildPropertyField(context, prop)),
            ],
            
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showNodeContextMenu(BuildContext context, Offset globalPos) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      globalPos & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete Node'),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        notifier.deleteNode(node.id);
      }
    });
  }

  Widget _buildInputRow(BuildContext context, FlowPortDefinition port, FlowPropertyDefinition? prop, bool isConnected) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPortTarget(context, port, isConnected), 
          Expanded(
            child: _buildInputContent(context, port, prop, isConnected),
          ),
        ],
      ),
    );
  }

  Widget _buildInputContent(BuildContext context, FlowPortDefinition port, FlowPropertyDefinition? prop, bool isConnected) {
    if (isConnected || prop == null) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          port.label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: _buildInlineProperty(context, prop),
    );
  }

  Widget _buildOutputRow(BuildContext context, FlowPortDefinition port) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6, left: 4),
              child: Text(
                port.label,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ),
          _buildPortSource(context, port),
        ],
      ),
    );
  }

  Widget _buildPortSource(BuildContext context, FlowPortDefinition port) {
    final color = _getPortColor(port);
    
    return Draggable<String>(
      data: node.id,
      feedback: const SizedBox.shrink(),
      hitTestBehavior: HitTestBehavior.opaque,
      onDragStarted: () {
        notifier.startConnectionDrag(node.id, port.key, false, port.type);
      },
      onDragUpdate: (details) {
        // CONVERT global position to canvas local
        final localPos = globalToLocal(details.globalPosition);
        notifier.updateConnectionDrag(localPos);
      },
      onDragEnd: (_) {
        notifier.endConnectionDrag(null, null);
      },
      child: Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black87, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildPortTarget(BuildContext context, FlowPortDefinition port, bool isConnected) {
    final color = _getPortColor(port);

    return GestureDetector(
      onSecondaryTap: () {
        if (isConnected) {
          notifier.deleteConnection(node.id, port.key);
        }
      },
      child: DragTarget<String>(
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          final finalColor = isHovering ? Colors.white : (isConnected ? Colors.white : color);
          
          return Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(
              color: finalColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isHovering ? Colors.greenAccent : Colors.black87, 
                width: 1.5
              ),
            ),
            // Show a tiny 'x' inside if connected to hint at right-click delete?
            // Or just rely on color change.
          );
        },
        onWillAccept: (data) {
          final draggingType = notifier.draggingPortType;
          if (draggingType == null) return false;
          if (draggingType == port.type) return true;
          if (draggingType == FlowPortType.execution && port.type != FlowPortType.execution) return false;
          if (draggingType != FlowPortType.execution && port.type == FlowPortType.execution) return false;
          if (draggingType == FlowPortType.any || port.type == FlowPortType.any) return true;
          return false;
        },
        onAccept: (data) {
          notifier.endConnectionDrag(node.id, port.key);
        },
      ),
    );
  }

  // ... (Rest of properties logic, colors, dialogs: same as before) ...
  
  Widget _buildPropertyField(BuildContext context, FlowPropertyDefinition prop) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Text("${prop.label}: ", style: const TextStyle(fontSize: 11, color: Colors.white54)),
          Expanded(child: _buildInlineProperty(context, prop)),
        ],
      ),
    );
  }

  Widget _buildInlineProperty(BuildContext context, FlowPropertyDefinition prop) {
    final val = node.properties[prop.key] ?? prop.defaultValue;

    if (prop.type == FlowPropertyType.tiledObjectRef) {
      final refValue = TiledObjectReference.fromDynamic(val);
      return PropertyTiledObjectPicker(
        definition: prop,
        value: refValue,
        onChanged: (newRef) => notifier.updateNodeProperty(node.id, prop.key, newRef),
      );
    }

    if (prop.type == FlowPropertyType.bool) {
      final boolValue = val == true;
      return GestureDetector(
        onTap: () => notifier.updateNodeProperty(node.id, prop.key, !boolValue),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(
                boolValue ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
                color: boolValue ? Colors.greenAccent : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                boolValue ? "True" : "False",
                style: const TextStyle(fontSize: 11, color: Colors.white),
              )
            ],
          ),
        ),
      );
    }

    if (prop.type == FlowPropertyType.color) {
      final color = _parseColor(val) ?? Colors.white;
      return GestureDetector(
        onTap: () => _showEditDialog(context, prop, val),
        child: Container(
          height: 16,
          width: 30,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.white30),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }

    String display = "$val";
    if (prop.type == FlowPropertyType.select) display = "$val ▼";

    return GestureDetector(
      onTap: () => _showEditDialog(context, prop, val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          display,
          style: const TextStyle(fontSize: 11, color: Colors.white),
          overflow: TextOverflow.ellipsis,
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
            initialValue: currentValue?.toString() ?? '',
            isNumeric: prop.type != FlowPropertyType.string,
            isFloat: prop.type == FlowPropertyType.float,
          ),
        );
        if (result != null && prop.type == FlowPropertyType.integer) result = int.tryParse(result);
        if (result != null && prop.type == FlowPropertyType.float) result = double.tryParse(result);
        break;

      case FlowPropertyType.select:
        result = await showDialog(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text("Select ${prop.label}"),
            children: (prop.options ?? []).map((opt) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, opt),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(opt),
              ),
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
          const Text("Missing Schema", style: TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }

  Color _getPortColor(FlowPortDefinition port) {
    if (port.customColor != null) return port.customColor!;
    switch (port.type) {
      case FlowPortType.execution: return Colors.white;
      case FlowPortType.string: return const Color(0xFFE91E63);
      case FlowPortType.number: return const Color(0xFF00E676);
      case FlowPortType.boolean: return const Color(0xFFD50000);
      case FlowPortType.vector2: return const Color(0xFFFFEA00);
      case FlowPortType.tiledObject: return const Color(0xFF2979FF);
      default: return Colors.grey;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'logic': return const Color(0xFF1565C0);
      case 'math': return const Color(0xFF00695C);
      case 'events': return const Color(0xFFC62828);
      case 'tiled': return const Color(0xFF2E7D32);
      case 'debug': return const Color(0xFF424242);
      default: return const Color(0xFF455A64);
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
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
            ? [widget.isFloat ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')) : FilteringTextInputFormatter.digitsOnly] 
            : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text("OK")),
      ],
    );
  }
}