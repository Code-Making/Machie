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
  // Local UI state, doesn't need to be in a provider
  ui.Image? _currentImage;

  @override
  void initState() {
    super.initState();
    _currentImage = widget.plugin.getImageForTab(widget.tab);
  }

  @override
  void didUpdateWidget(covariant GlitchEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync the local image when an undo/redo happens
    final newImage = widget.plugin.getImageForTab(widget.tab);
    if (newImage != _currentImage) {
      setState(() {
        _currentImage = newImage;
      });
    }
  }

  void _onPanStart(DragStartDetails details) {
    widget.plugin.beginGlitchStroke(widget.tab);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final newImage = widget.plugin.applyGlitchEffect(
      tab: widget.tab,
      position: details.localPosition,
    );
    if (newImage != _currentImage) {
      setState(() {
        _currentImage = newImage;
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    widget.plugin.endGlitchStroke(widget.tab, ref);
  }

  @override
  Widget build(BuildContext context) {
    final image = _currentImage;
    if (image == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Center(
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: CustomPaint(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          painter: _ImagePainter(image),
        ),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: image,
      filterQuality: FilterQuality.none,
      fit: BoxFit.contain,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) => image != oldDelegate.image;
}