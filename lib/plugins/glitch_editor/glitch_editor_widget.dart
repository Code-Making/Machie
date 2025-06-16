// lib/plugins/glitch_editor/glitch_editor_widget.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glitch_editor_models.dart';
import 'glitch_editor_plugin.dart';

class GlitchEditorWidget extends ConsumerStatefulWidget {
  final GlitchEditorTab tab;
  final GlitchEditorPlugin plugin;

  const GlitchEditorWidget({
    super.key,
    required this.tab,
    required this.plugin,
  });

  @override
  ConsumerState<GlitchEditorWidget> createState() => _GlitchEditorWidgetState();
}

class _GlitchEditorWidgetState extends ConsumerState<GlitchEditorWidget> {
  final TransformationController _transformationController = TransformationController();
  
  // This now holds the points for the *entire* stroke, in the image's coordinate space.
  List<Offset> _currentStrokePoints = [];
  GlitchBrushSettings? _liveBrushSettings;
  
  // We hold a local reference to the image to drive the painter.
  ui.Image? _displayImage;

  @override
  void initState() {
    super.initState();
    _displayImage = widget.plugin.getImageForTab(widget.tab);
  }

  @override
  void didUpdateWidget(covariant GlitchEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When an external change happens (like a reset), get the new image from the plugin.
    final newImage = widget.plugin.getImageForTab(widget.tab);
    if (newImage != _displayImage) {
      setState(() {
        _displayImage = newImage;
        _currentStrokePoints = [];
        _liveBrushSettings = null;
      });
    }
  }

  void _onInteractionStart(ScaleStartDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;

    _liveBrushSettings = ref.read(widget.plugin.brushSettingsProvider).copyWith();
    widget.plugin.beginGlitchStroke(widget.tab);
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;
    
    // This is the correct transformation logic.
    final matrix = _transformationController.value.clone()..invert();
    final transformedPoint = MatrixUtils.transformPoint(matrix, details.focalPoint);
    
    setState(() {
      _currentStrokePoints.add(transformedPoint);
    });
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;

    final newImage = widget.plugin.applyGlitchStroke(
      tab: widget.tab,
      points: _currentStrokePoints,
      settings: _liveBrushSettings!,
      ref: ref,
    );
    
    // Update the local display image and clear the live stroke.
    // This avoids a full widget tree rebuild.
    setState(() {
      _displayImage = newImage;
      _currentStrokePoints = [];
      _liveBrushSettings = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_displayImage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final isZoomMode = ref.watch(widget.plugin.isZoomModeProvider);
    final isSliding = ref.watch(widget.plugin.isSlidingProvider);
    final brushSettings = ref.watch(widget.plugin.brushSettingsProvider);
    final screenWidth = MediaQuery.of(context).size.width;

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.1,
      maxScale: 4.0,
      panEnabled: isZoomMode,
      scaleEnabled: isZoomMode,
      onInteractionStart: _onInteractionStart,
      onInteractionUpdate: _onInteractionUpdate,
      onInteractionEnd: _onInteractionEnd,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(_displayImage!.width.toDouble(), _displayImage!.height.toDouble()),
              painter: _ImagePainter(
                baseImage: _displayImage!,
              ),
            ),
            if (isSliding)
              IgnorePointer(child: _BrushPreview(settings: brushSettings, screenWidth: screenWidth)),
          ],
        ),
      ),
    );
  }
}

class _BrushPreview extends StatelessWidget {
  final GlitchBrushSettings settings;
  final double screenWidth;
  const _BrushPreview({required this.settings, required this.screenWidth});

  @override
  Widget build(BuildContext context) {
    final radius = settings.radius * screenWidth;
    return Container(
      width: radius,
      height: radius,
      decoration: BoxDecoration(
        shape: settings.shape == GlitchBrushShape.circle ? BoxShape.circle : BoxShape.rectangle,
        color: Colors.white.withOpacity(0.3),
        border: Border.all(color: Colors.white.withOpacity(0.7), width: 2),
      ),
    );
  }
}

// The painter is now much simpler. It just draws the image.
class _ImagePainter extends CustomPainter {
  final ui.Image baseImage;

  _ImagePainter({ required this.baseImage });

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(canvas: canvas, rect: Rect.fromLTWH(0, 0, size.width, size.height), image: baseImage, filterQuality: FilterQuality.none, fit: BoxFit.contain);
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return baseImage != oldDelegate.baseImage;
  }
}