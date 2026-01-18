// FILE: lib/editor/plugins/flow_graph/utils/flow_layout_utils.dart

import 'dart:ui';
import '../models/flow_graph_models.dart';
import '../models/flow_schema_models.dart';

class FlowLayoutUtils {
  // Constants shared with SchemaNodeWidget layout
  static const double headerHeight = 40.0; // Updated to match SchemaNodeWidget height
  static const double rowHeight = 32.0;
  static const double nodeWidth = 200.0;

  static Offset? getPortPosition(
    FlowNode node, 
    String portKey, 
    bool isInput, 
    FlowNodeType? schema
  ) {
    if (schema == null) return node.position + const Offset(10, 10);

    final list = isInput ? schema.inputs : schema.outputs;
    final index = list.indexWhere((p) => p.key == portKey);
    
    if (index == -1) return node.position;

    // Y Calculation: Node Top + Header + (Index * RowHeight) + (RowHeight / 2)
    final y = node.position.dy + 
              headerHeight + 
              8.0 + // Spacing defined in SchemaNodeWidget
              (index * rowHeight) + 
              (rowHeight / 2); 
    
    final x = isInput 
        ? node.position.dx + 6.0 
        : node.position.dx + nodeWidth - 6.0; 

    return Offset(x, y);
  }

  static Path generateConnectionPath(Offset p1, Offset p2) {
    final path = Path();
    path.moveTo(p1.dx, p1.dy);

    final dx = (p2.dx - p1.dx).abs();
    final curvature = (dx / 2).clamp(30.0, 150.0);

    path.cubicTo(
      p1.dx + curvature, p1.dy,
      p2.dx - curvature, p2.dy,
      p2.dx, p2.dy,
    );
    return path;
  }

  static bool isPointNearPath(Offset point, Path path, {double threshold = 10.0}) {
    final thresholdSq = threshold * threshold;
    final metrics = path.computeMetrics();
    
    for (final metric in metrics) {
      // Sample density: check every 6 pixels along the curve
      for (double d = 0; d < metric.length; d += 6.0) {
        final pos = metric.getTangentForOffset(d)!.position;
        if ((point - pos).distanceSquared < thresholdSq) {
          return true;
        }
      }
    }
    return false;
  }
}