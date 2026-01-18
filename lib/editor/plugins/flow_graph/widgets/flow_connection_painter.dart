// FILE: lib/editor/plugins/flow_graph/widgets/flow_connection_painter.dart

import 'package:flutter/material.dart';
import '../models/flow_graph_models.dart';
import '../models/flow_schema_models.dart';

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
      final outPos = _getPortPosition(conn.outputNodeId, conn.outputPortKey, isInput: false);
      final inPos = _getPortPosition(conn.inputNodeId, conn.inputPortKey, isInput: true);

      if (outPos != null && inPos != null) {
        paint.color = Colors.white70;
        _drawFixedBezier(canvas, outPos, inPos, paint);
      }
    }

    // Draw pending drag
    if (pendingConnection != null && pendingCursor != null) {
      final startPos = _getPortPosition(
        pendingConnection!.outputNodeId, 
        pendingConnection!.outputPortKey, 
        isInput: false 
      );
      
      if (startPos != null) {
        paint.color = Colors.yellowAccent;
        _drawFixedBezier(canvas, startPos, pendingCursor!, paint);
      }
    }
  }

  void _drawFixedBezier(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final path = Path();
    path.moveTo(p1.dx, p1.dy);

    // Fixed horizontal curvature
    // Ensure the line always goes OUT horizontally first
    final dx = (p2.dx - p1.dx).abs();
    final curvature = (dx / 2).clamp(30.0, 150.0);

    path.cubicTo(
      p1.dx + curvature, p1.dy, // Control 1: Right of Start
      p2.dx - curvature, p2.dy, // Control 2: Left of End
      p2.dx, p2.dy,             // End
    );

    canvas.drawPath(path, paint);
  }

  Offset? _getPortPosition(String nodeId, String portKey, {required bool isInput}) {
    // Basic estimation based on standard node layout.
    // In a production app, nodes should report their port positions via RenderBox.
    
    final node = nodes.firstWhere((n) => n.id == nodeId, orElse: () => FlowNode(id: '', type: '', position: Offset.zero));
    if (node.id.isEmpty) return null;

    final schema = schemaMap[node.type];
    if (schema == null) return node.position + const Offset(10, 10);

    const headerHeight = 32.0 + 8.0; // Header + spacing
    const rowHeight = 28.0 + 4.0; // Height + padding
    const portOffsetY = 14.0; // Half row height

    final list = isInput ? schema.inputs : schema.outputs;
    final index = list.indexWhere((p) => p.key == portKey);
    
    if (index == -1) return node.position;

    final y = node.position.dy + headerHeight + (index * rowHeight) + portOffsetY;
    
    // NOTE: This width must match the constraints in SchemaNodeWidget
    // We used min 160, max 240. Let's assume an average or measure text.
    // For now, hardcoding an estimated width or passing it would be ideal.
    // Let's assume standard width for calculation. 
    const nodeWidth = 200.0; 
    
    final x = isInput 
        ? node.position.dx + 6.0 // Padding left
        : node.position.dx + nodeWidth - 6.0; // Padding right

    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant FlowConnectionPainter old) => true;
}