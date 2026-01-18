// FILE: lib/editor/plugins/flow_graph/widgets/flow_graph_canvas.dart

import 'package:flutter/material.dart';
import '../flow_graph_notifier.dart';
import '../models/flow_schema_models.dart';
import 'schema_node_widget.dart';
import 'flow_connection_painter.dart';

class FlowGraphCanvas extends StatefulWidget {
  final FlowGraphNotifier notifier;
  final Map<String, FlowNodeType> schemaMap;

  const FlowGraphCanvas({
    super.key,
    required this.notifier,
    required this.schemaMap,
  });

  @override
  State<FlowGraphCanvas> createState() => _FlowGraphCanvasState();
}

class _FlowGraphCanvasState extends State<FlowGraphCanvas> {
  final TransformationController _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    // Initialize viewport from graph state if saved
    final initialPos = widget.notifier.graph.viewportPosition;
    final initialScale = widget.notifier.graph.viewportScale;
    
    // Setup Matrix4 based on saved state
    final matrix = Matrix4.identity()
      ..translate(initialPos.dx, initialPos.dy)
      ..scale(initialScale);
    _transformCtrl.value = matrix;
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  void _onPaneTap() {
    widget.notifier.clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        final graph = widget.notifier.graph;
        final nodes = graph.nodes;
        final connections = graph.connections;

        return Stack(
          children: [
            // Infinite Canvas
            GestureDetector(
              onTap: _onPaneTap,
              child: InteractiveViewer(
                transformationController: _transformCtrl,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.1,
                maxScale: 2.0,
                constrained: false, // Allows infinite scrolling
                child: SizedBox(
                  width: 50000, // Large virtual area, effectively infinite
                  height: 50000,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1. Grid Painter
                      Positioned.fill(
                        child: CustomPaint(
                          painter: GridPainter(
                            scale: _transformCtrl.value.getMaxScaleOnAxis(),
                            offset: Offset.zero, // InteractiveViewer handles visual offset
                          ),
                        ),
                      ),

                      // 2. Connections Layer
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FlowConnectionPainter(
                            connections: connections,
                            nodes: nodes,
                            schemaMap: widget.schemaMap,
                            pendingConnection: widget.notifier.pendingConnection,
                            pendingCursor: widget.notifier.pendingConnectionPointer,
                          ),
                        ),
                      ),

                      // 3. Nodes Layer
                      // We shift them to the center of our large SizedBox to allow scrolling in negative directions conceptually
                      // Or simply treat 25000,25000 as 0,0. 
                      // For simplicity here, we assume node positions are absolute within this stack.
                      ...nodes.map((node) {
                        return Positioned(
                          left: node.position.dx,
                          top: node.position.dy,
                          child: SchemaNodeWidget(
                            node: node,
                            schema: widget.schemaMap[node.type],
                            isSelected: widget.notifier.selectedNodeIds.contains(node.id),
                            notifier: widget.notifier,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            
            // TODO: UI Overlays (Mini-map, Toolbar)
          ],
        );
      },
    );
  }
}

class GridPainter extends CustomPainter {
  final double scale;
  final Offset offset; // Used if we were doing manual matrix math, less needed with InteractiveViewer

  GridPainter({required this.scale, required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF1E1E1E);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1.0;

    const gridSize = 20.0;
    // Draw simple grid
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter old) => false;
}