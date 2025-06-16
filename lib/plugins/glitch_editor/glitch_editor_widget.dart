// lib/plugins/glitch_editor/glitch_editor_widget.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glitch_editor_math.dart';
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
  List<Offset> _liveStrokePoints = [];
  GlitchBrushSettings? _liveBrushSettings;

  @override
  void didUpdateWidget(covariant GlitchEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab != oldWidget.tab) {
      setState(() {
        _liveStrokePoints = [];
        _liveBrushSettings = null;
      });
    }
  }

  void _onPanStart(DragStartDetails details) {
    _liveBrushSettings = ref.read(widget.plugin.brushSettingsProvider).copyWith();
    widget.plugin.beginGlitchStroke(widget.tab);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      final matrix = _transformationController.value.clone()..invert();
      final transformedPoint = MatrixUtils.transformPoint(matrix, details.localPosition);
      _liveStrokePoints.add(transformedPoint);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // CORRECTED: Pass the widget's size to the plugin.
    widget.plugin.applyGlitchStroke(
      tab: widget.tab,
      points: _liveStrokePoints,
      settings: _liveBrushSettings!,
      widgetSize: context.size!, 
      ref: ref,
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseImage = widget.plugin.getImageForTab(widget.tab);
    if (baseImage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final isZoomMode = ref.watch(widget.plugin.isZoomModeProvider);
    final isSliding = ref.watch(widget.plugin.isSlidingProvider);
    final brushSettings = ref.watch(widget.plugin.brushSettingsProvider);

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.1,
      maxScale: 4.0,
      panEnabled: isZoomMode,
      scaleEnabled: isZoomMode,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onPanStart: isZoomMode ? null : _onPanStart,
              onPanUpdate: isZoomMode ? null : _onPanUpdate,
              onPanEnd: isZoomMode ? null : _onPanEnd,
              child: CustomPaint(
                size: Size(baseImage.width.toDouble(), baseImage.height.toDouble()),
                painter: _ImagePainter(
                  baseImage: baseImage,
                  liveStroke: _liveStrokePoints,
                  liveBrushSettings: _liveBrushSettings,
                ),
              ),
            ),
            // Brush Preview Overlay
            if (isSliding)
              IgnorePointer(
                child: _BrushPreview(settings: brushSettings),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrushPreview extends StatelessWidget {
  final GlitchBrushSettings settings;
  const _BrushPreview({required this.settings});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final radius = settings.radius * screenWidth * 0.5; // Half because it's a radius

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: settings.shape == GlitchBrushShape.circle ? BoxShape.circle : BoxShape.rectangle,
        border: Border.all(color: Colors.white.withOpacity(0.7), width: 2),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image baseImage;
  final List<Offset> liveStroke;
  final GlitchBrushSettings? liveBrushSettings;
  final Random _random = Random();

  _ImagePainter({
    required this.baseImage,
    required this.liveStroke,
    this.liveBrushSettings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: baseImage,
      filterQuality: FilterQuality.none,
      fit: BoxFit.contain,
    );

    if (liveBrushSettings != null) {
      final point = liveStroke.lastOrNull;
      if (point == null) return;
      
      final imageSize = Size(baseImage.width.toDouble(), baseImage.height.toDouble());
      final transformedPoint = transformWidgetPointToImagePoint(
          point,
          widgetSize: size,
          imageSize: imageSize,
        );

      switch (liveBrushSettings!.type) {
        case GlitchBrushType.scatter:
          _applyScatter(canvas, transformedPoint, liveBrushSettings!);
          break;
        case GlitchBrushType.repeater:
          _applyRepeater(canvas, transformedPoint, liveBrushSettings!);
          break;
      }
    }
  }
  
  void _applyScatter(Canvas canvas, Offset pos, GlitchBrushSettings settings) {
      final screenWidth = canvas.getLocalClipBounds().width;
      final radius = settings.radius * screenWidth;
      final count = (settings.frequency * 50).toInt().clamp(1, 50);

      for (int i = 0; i < count; i++) {
        final srcX = pos.dx + _random.nextDouble() * radius * 2 - radius;
        final srcY = pos.dy + _random.nextDouble() * radius * 2 - radius;
        final dstX = pos.dx + _random.nextDouble() * radius * 2 - radius;
        final dstY = pos.dy + _random.nextDouble() * radius * 2 - radius;
        final size = settings.minBlockSize + _random.nextDouble() * (settings.maxBlockSize - settings.minBlockSize);
        canvas.drawImageRect(baseImage, Rect.fromLTWH(srcX, srcY, size, size), Rect.fromLTWH(dstX, dstY, size, size), Paint());
      }
  }

  void _applyRepeater(Canvas canvas, Offset pos, GlitchBrushSettings settings) {
      final screenWidth = canvas.getLocalClipBounds().width;
      final radius = settings.radius * screenWidth;
      final srcRect = Rect.fromCenter(center: pos, width: radius, height: radius);
      final spacing = (settings.frequency * radius).clamp(5.0, 100.0);
      for(int i = -3; i <= 3; i++) {
          if (i == 0) continue;
          final offset = Offset(i * spacing, 0);
          canvas.drawImageRect(baseImage, srcRect, srcRect.shift(offset), Paint()..blendMode = BlendMode.difference);
      }
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return baseImage != oldDelegate.baseImage || !const DeepCollectionEquality().equals(liveStroke, oldDelegate.liveStroke);
  }
}