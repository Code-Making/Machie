// FILE: lib/editor/plugins/flow_graph/widgets/flow_graph_canvas.dart

import 'package:flutter/material.dart';
import '../flow_graph_notifier.dart';
import '../models/flow_schema_models.dart';
import '../flow_graph_settings_model.dart';
import 'schema_node_widget.dart';
import 'flow_connection_painter.dart';

class FlowGraphCanvas extends StatefulWidget {
  final FlowGraphNotifier notifier;
  final Map<String, FlowNodeType> schemaMap;
  final FlowGraphSettings settings;

  const FlowGraphCanvas({
    super.key,
    required this.notifier,
    required this.schemaMap,
    required this.settings,
  });

  @override
  State<FlowGraphCanvas> createState() => _FlowGraphCanvasState();
}

class _FlowGraphCanvasState extends State<FlowGraphCanvas> {
  final TransformationController _transformCtrl = TransformationController();
  final GlobalKey _stackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final initialPos = widget.notifier.graph.viewportPosition;
    final initialScale = widget.notifier.graph.viewportScale;
    final matrix = Matrix4.identity()..translate(initialPos.dx, initialPos.dy)..scale(initialScale);
    _transformCtrl.value = matrix;
    // Listen to changes to rebuild and update scale for drag logic
    _transformCtrl.addListener(() {
      if (mounted) setState(() {}); 
    });
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  Offset _globalToLocal(Offset global) {
    final RenderBox? box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) return box.globalToLocal(global);
    return global;
  }

  @override
  Widget build(BuildContext context) {
    // Get current scale to pass to nodes for drag correction
    final currentScale = _transformCtrl.value.getMaxScaleOnAxis();

    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        final graph = widget.notifier.graph;
        return Stack(
          children: [
            GestureDetector(
              onTap: () => widget.notifier.clearSelection(),
              child: InteractiveViewer(
                transformationController: _transformCtrl,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.1,
                maxScale: 2.0,
                constrained: false,
                child: SizedBox(
                  width: 50000,
                  height: 50000,
                  child: Stack(
                    key: _stackKey,
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: GridPainter(
                            scale: currentScale,
                            offset: Offset.zero,
                            settings: widget.settings,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FlowConnectionPainter(
                            connections: graph.connections,
                            nodes: graph.nodes,
                            schemaMap: widget.schemaMap,
                            pendingConnection: widget.notifier.pendingConnection,
                            pendingCursor: widget.notifier.pendingConnectionPointer,
                          ),
                        ),
                      ),
                      ...graph.nodes.map((node) {
                        return Positioned(
                          left: node.position.dx,
                          top: node.position.dy,
                          child: SchemaNodeWidget(
                            node: node,
                            schema: widget.schemaMap[node.type],
                            isSelected: widget.notifier.selectedNodeIds.contains(node.id),
                            notifier: widget.notifier,
                            globalToLocal: _globalToLocal,
                            canvasScale: currentScale, // NEW: Pass scale
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class GridPainter extends CustomPainter {
  final double scale;
  final Offset offset;
  final FlowGraphSettings settings;

  GridPainter({
    required this.scale,
    required this.offset,
    required this.settings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Color(settings.backgroundColorValue);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final linePaint = Paint()
      ..color = Color(settings.gridColorValue)
      ..strokeWidth = settings.gridThickness;

    final gridSize = settings.gridSpacing;

    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter old) =>
      old.scale != scale || old.settings != settings;
}