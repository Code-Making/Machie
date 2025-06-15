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
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _liveStrokePoints.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    widget.plugin.applyGlitchStroke(
      tab: widget.tab,
      points: _liveStrokePoints,
      settings: _liveBrushSettings!,
      widgetSize: context.size!, // Pass the widget's size for transformation
      ref: ref,
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseImage = widget.plugin.getImageForTab(widget.tab);
    if (baseImage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Center(
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: CustomPaint(
          size: Size(baseImage.width.toDouble(), baseImage.height.toDouble()),
          painter: _ImagePainter(
            baseImage: baseImage,
            liveStroke: _liveStrokePoints,
            liveBrushSettings: _liveBrushSettings,
          ),
        ),
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
      final imageSize = Size(baseImage.width.toDouble(), baseImage.height.toDouble());
      for (final point in liveStroke) {
        // CORRECTED: Transform the point from widget space to image space
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
  }
  
  // The painter now draws directly onto the main canvas, not a temporary one.
  void _applyScatter(Canvas canvas, Offset pos, GlitchBrushSettings settings) {
    final radius = settings.radius;
    // CORRECTED: Reduced density for a less overwhelming effect
    final count = (radius * settings.density * 0.5).toInt().clamp(1, 10);
    for (int i = 0; i < count; i++) {
        final srcX = pos.dx + _random.nextDouble() * radius * 2 - radius;
        final srcY = pos.dy + _random.nextDouble() * radius * 2 - radius;
        final dstX = pos.dx + _random.nextDouble() * radius * 2 - radius;
        final dstY = pos.dy + _random.nextDouble() * radius * 2 - radius;
        final size = 2 + _random.nextDouble() * 4;
        canvas.drawImageRect(baseImage, Rect.fromLTWH(srcX, srcY, size, size), Rect.fromLTWH(dstX, dstY, size, size), Paint());
    }
  }

  void _applyRepeater(Canvas canvas, Offset pos, GlitchBrushSettings settings) {
      final radius = settings.radius;
      final srcRect = Rect.fromCenter(center: pos, width: radius, height: radius);
      final spacing = settings.repeatSpacing.toDouble() * (radius / 20.0);
      for(int i = -2; i <= 2; i++) { // CORRECTED: Reduced repetitions
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