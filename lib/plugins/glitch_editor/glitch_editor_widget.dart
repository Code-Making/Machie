// lib/plugins/glitch_editor/glitch_editor_widget.dart
import 'dart:ui' as ui;
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
  // Local UI state for the live effect overlay
  List<Offset> _liveStrokePoints = [];
  GlitchBrushSettings? _liveBrushSettings;

  @override
  void didUpdateWidget(covariant GlitchEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the tab instance changes (due to reset), clear the live stroke
    // to force the painter to redraw with the new base image.
    if (widget.tab != oldWidget.tab) {
      setState(() {
        _liveStrokePoints = [];
        _liveBrushSettings = null;
      });
    }
  }

  void _onPanStart(DragStartDetails details) {
    // Capture the brush settings at the start of the stroke
    _liveBrushSettings = ref.read(widget.plugin.brushSettingsProvider).copyWith();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Performance: Only add points to a list and trigger a repaint.
    // Do not create a new image here.
    setState(() {
      _liveStrokePoints.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // Performance: Apply the effect only once at the end of the stroke.
    widget.plugin.applyGlitchStroke(
      tab: widget.tab,
      points: _liveStrokePoints,
      settings: _liveBrushSettings!,
      ref: ref,
    );
    // The plugin will notify AppNotifier, which triggers didUpdateWidget,
    // which will clear the live stroke.
  }

  @override
  Widget build(BuildContext context) {
    // The base image comes directly from the plugin's hot state.
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
          // The painter now receives the base image AND the live effect data.
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
    // 1. Draw the stable base image.
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: baseImage,
      filterQuality: FilterQuality.none,
      fit: BoxFit.contain,
    );

    // 2. If there's a live stroke, draw the glitch effect on top.
    if (liveBrushSettings != null) {
      for (final point in liveStroke) {
        switch (liveBrushSettings!.type) {
          case GlitchBrushType.scatter:
            _applyScatter(canvas, baseImage, point, liveBrushSettings!);
            break;
          case GlitchBrushType.repeater:
            _applyRepeater(canvas, baseImage, point, liveBrushSettings!);
            break;
        }
      }
    }
  }
  
  void _applyScatter(Canvas canvas, ui.Image source, Offset pos, GlitchBrushSettings settings) {
    final radius = settings.radius;
    final count = (radius * radius * settings.density * 0.05).toInt().clamp(1, 50);
    for (int i = 0; i < count; i++) {
        final srcX = pos.dx + _random.nextDouble() * radius * 2 - radius;
        final srcY = pos.dy + _random.nextDouble() * radius * 2 - radius;
        final dstX = pos.dx + _random.nextDouble() * radius * 2 - radius;
        final dstY = pos.dy + _random.nextDouble() * radius * 2 - radius;
        final size = 2 + _random.nextDouble() * 4;
        canvas.drawImageRect(source, Rect.fromLTWH(srcX, srcY, size, size), Rect.fromLTWH(dstX, dstY, size, size), Paint());
    }
  }

  void _applyRepeater(Canvas canvas, ui.Image source, Offset pos, GlitchBrushSettings settings) {
      final radius = settings.radius;
      final srcRect = Rect.fromCenter(center: pos, width: radius, height: radius);
      final spacing = settings.repeatSpacing.toDouble() * (radius / 20.0);
      for(int i = -3; i <= 3; i++) {
          if (i == 0) continue;
          final offset = Offset(i * spacing, i * spacing * 0.5);
          canvas.drawImageRect(source, srcRect, srcRect.shift(offset), Paint()..blendMode = BlendMode.difference);
      }
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return baseImage != oldDelegate.baseImage || !const DeepCollectionEquality().equals(liveStroke, oldDelegate.liveStroke);
  }
}