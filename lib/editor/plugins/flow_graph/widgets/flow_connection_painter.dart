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

  // Constants must match SchemaNodeWidget exactly
  static const double _headerHeight = 32.0;
  static const double _headerSpacing = 8.0;
  static const double _rowHeight = 32.0; // Enforced height in widget
  static const double _rowPadding = 0.0; // Widget uses this as internal constraints

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

    final dx = (p2.dx - p1.dx).abs();
    final curvature = (dx / 2).clamp(30.0, 150.0);

    path.cubicTo(
      p1.dx + curvature, p1.dy,
      p2.dx - curvature, p2.dy,
      p2.dx, p2.dy,
    );

    canvas.drawPath(path, paint);
  }

  Offset? _getPortPosition(String nodeId, String portKey, {required bool isInput}) {
    final node = nodes.firstWhere(
      (n) => n.id == nodeId, 
      orElse: () => FlowNode(id: '', type: '', position: Offset.zero)
    );
    if (node.id.isEmpty) return null;

    final schema = schemaMap[node.type];
    if (schema == null) return node.position + const Offset(10, 10);

    final list = isInput ? schema.inputs : schema.outputs;
    final index = list.indexWhere((p) => p.key == portKey);
    
    if (index == -1) return node.position;

    // Y Calculation
    // Start at node Y
    // Add Header + Spacing
    // Add N rows
    // Add Half row to center
    final y = node.position.dy + 
              _headerHeight + 
              _headerSpacing + 
              (index * _rowHeight) + 
              (_rowHeight / 2); // Center of row
    
    // X Calculation
    // Assuming Node Width is fixed 200.0 as per SchemaNodeWidget constraints/defaults
    const nodeWidth = 200.0; 
    
    final x = isInput 
        ? node.position.dx + 6.0 // Center of left dot (width 12 / 2 + margins)
        : node.position.dx + nodeWidth - 6.0; // Center of right dot

    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant FlowConnectionPainter old) => true;
}