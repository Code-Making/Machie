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
        paint.color = Colors.white; // TODO: Get color from schema type
        _drawBezier(canvas, outPos, inPos, paint);
      }
    }

    // Draw pending drag
    if (pendingConnection != null && pendingCursor != null) {
      final startPos = _getPortPosition(
        pendingConnection!.outputNodeId, 
        pendingConnection!.outputPortKey, 
        isInput: false // Assuming dragging from Output
      );
      
      if (startPos != null) {
        paint.color = Colors.yellow;
        _drawBezier(canvas, startPos, pendingCursor!, paint);
      }
    }
  }

  void _drawBezier(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final path = Path();
    path.moveTo(p1.dx, p1.dy);

    final distance = (p2.dx - p1.dx).abs();
    final controlOffset = distance * 0.5;

    // Cubic bezier for smooth 'S' curve
    path.cubicTo(
      p1.dx + controlOffset, p1.dy, // Control point 1 (right of start)
      p2.dx - controlOffset, p2.dy, // Control point 2 (left of end)
      p2.dx, p2.dy,                 // End point
    );

    canvas.drawPath(path, paint);
  }

  // NOTE: This assumes a fixed layout logic for nodes. 
  // Ideally, widgets report their positions.
  Offset? _getPortPosition(String nodeId, String portKey, {required bool isInput}) {
    final node = nodes.firstWhere((n) => n.id == nodeId, orElse: () => FlowNode(id: '', type: '', position: Offset.zero));
    if (node.id.isEmpty) return null;

    final schema = schemaMap[node.type];
    if (schema == null) return node.position + const Offset(10, 10); // Fallback

    const headerHeight = 40.0;
    const portRowHeight = 24.0;
    const portOffsetY = 12.0; // Center of row

    final list = isInput ? schema.inputs : schema.outputs;
    final index = list.indexWhere((p) => p.key == portKey);
    
    if (index == -1) return node.position; // Error fallback

    final y = node.position.dy + headerHeight + (index * portRowHeight) + portOffsetY;
    
    // Width is tricky without measurement. Assume standard width or specific logic.
    // Let's assume standard 150 width for now.
    final x = isInput 
        ? node.position.dx 
        : node.position.dx + 150.0; 

    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant FlowConnectionPainter old) => true;
}