// FILE: lib/editor/plugins/flow_graph/widgets/flow_connection_painter.dart

import 'package:flutter/material.dart';
import '../models/flow_graph_models.dart';
import '../models/flow_schema_models.dart';
import '../utils/flow_layout_utils.dart'; // Import Utils

class FlowConnectionPainter extends CustomPainter {
  final List<FlowConnection> connections;
  final List<FlowNode> nodes;
  final Map<String, FlowNodeType> schemaMap;
  final FlowConnection? pendingConnection;
  final Offset? pendingCursor;

  FlowConnectionPainter({
    required this.connections,
    required this.nodes,
    required this.schemaMap,
    this.pendingConnection,
    this.pendingCursor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Draw existing connections
    for (final conn in connections) {
      final outNode = _getNode(conn.outputNodeId);
      final inNode = _getNode(conn.inputNodeId);
      
      final outPos = FlowLayoutUtils.getPortPosition(outNode, conn.outputPortKey, false, schemaMap[outNode.type]);
      final inPos = FlowLayoutUtils.getPortPosition(inNode, conn.inputPortKey, true, schemaMap[inNode.type]);

      if (outPos != null && inPos != null) {
        paint.color = Colors.white70;
        final path = FlowLayoutUtils.generateConnectionPath(outPos, inPos);
        canvas.drawPath(path, paint);
      }
    }

    // Draw pending drag
    if (pendingConnection != null && pendingCursor != null) {
      final outNode = _getNode(pendingConnection!.outputNodeId);
      final startPos = FlowLayoutUtils.getPortPosition(
        outNode, 
        pendingConnection!.outputPortKey, 
        false, 
        schemaMap[outNode.type]
      );
      
      if (startPos != null) {
        paint.color = Colors.yellowAccent;
        final path = FlowLayoutUtils.generateConnectionPath(startPos, pendingCursor!);
        canvas.drawPath(path, paint);
      }
    }
  }

  FlowNode _getNode(String id) {
    return nodes.firstWhere(
      (n) => n.id == id, 
      orElse: () => FlowNode(id: '', type: '', position: Offset.zero)
    );
  }

  @override
  bool shouldRepaint(covariant FlowConnectionPainter old) => true;
}