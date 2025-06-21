// lib/plugins/glitch_editor/glitch_editor_widget.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glitch_editor_models.dart';
import 'glitch_editor_plugin.dart';

import '../../services/editor_service.dart';

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
  final TransformationController _transformationController =
      TransformationController();

  List<Offset> _currentStrokePoints = [];
  GlitchBrushSettings? _liveBrushSettings;
  ui.Image? _displayImage;

  Offset _imageDisplayOffset = Offset.zero;
  double _imageScale = 1.0;

  @override
  void initState() {
    super.initState();
    // REFACTOR: The initial image is retrieved here. Subsequent updates will come from the watcher.
    _displayImage = widget.plugin.getImageForTab(ref, widget.tab);
    _transformationController.addListener(_updateImageDisplayParams);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_updateImageDisplayParams);
    super.dispose();
  }

  void _updateImageDisplayParams() {
    if (_displayImage == null || !context.mounted || context.size == null) return;
    final imageSize = Size(_displayImage!.width.toDouble(), _displayImage!.height.toDouble());
    final widgetSize = context.size!;
    final fitted = applyBoxFit(BoxFit.contain, imageSize, widgetSize);
    final destinationSize = fitted.destination;
    _imageDisplayOffset = Offset(
      (widgetSize.width - destinationSize.width) / 2.0,
      (widgetSize.height - destinationSize.height) / 2.0,
    );
    _imageScale = destinationSize.width / imageSize.width;
  }

  void _onInteractionStart(ScaleStartDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;
    _liveBrushSettings = ref.read(widget.plugin.brushSettingsProvider).copyWith();
    // REFACTOR: Pass the ref to the plugin method
    widget.plugin.beginGlitchStroke(ref, widget.tab);
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;
    final inverseViewerMatrix = Matrix4.tryInvert(_transformationController.value);
    if (inverseViewerMatrix == null) return;
    final localPoint = MatrixUtils.transformPoint(inverseViewerMatrix, details.localFocalPoint);
    final imagePoint = _convertToImageCoordinates(localPoint);
    setState(() {
      _currentStrokePoints.add(imagePoint);
    });
  }

  Offset _convertToImageCoordinates(Offset widgetPoint) {
    final adjustedPoint = widgetPoint - _imageDisplayOffset;
    return Offset(adjustedPoint.dx / _imageScale, adjustedPoint.dy / _imageScale);
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;
    final viewerScale = _transformationController.value.getMaxScaleOnAxis();
    final safeScale = viewerScale.isFinite ? viewerScale : 1.0;
    final combinedScale = _imageScale * safeScale;

    final newImage = widget.plugin.applyGlitchStroke(
      tab: widget.tab,
      points: _currentStrokePoints,
      settings: _liveBrushSettings!.copyWith(
        radius: _liveBrushSettings!.radius / combinedScale,
        minBlockSize: _liveBrushSettings!.minBlockSize / combinedScale,
        maxBlockSize: _liveBrushSettings!.maxBlockSize / combinedScale,
      ),
      ref: ref,
    );

    // After applying the stroke, the state within the manager has changed.
    // The widget will be rebuilt by the watcher below, so we don't need to
    // manually set _displayImage here.
    setState(() {
      _currentStrokePoints = [];
      _liveBrushSettings = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // REFACTOR: Watch for changes in the tab's state and update the display image.
    _displayImage = ref.watch(
      tabStateManagerProvider
          .select((s) => (s[widget.tab.file.uri] as GlitchTabState?)?.image),
    );

    if (_displayImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateImageDisplayParams();
    });

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
              painter: _ImagePainter(baseImage: _displayImage!),
            ),
            if (isSliding)
              IgnorePointer(
                child: _BrushPreview(settings: brushSettings, screenWidth: screenWidth),
              ),
          ],
        ),
      ),
    );
  }
}

// ... (_BrushPreview and _ImagePainter are unchanged) ...
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
        shape:
            settings.shape == GlitchBrushShape.circle
                ? BoxShape.circle
                : BoxShape.rectangle,
        color: Colors.white.withOpacity(0.3),
        border: Border.all(
          color: Colors.white.withOpacity(0.7),
          width: 2,
        ),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image baseImage;

  _ImagePainter({required this.baseImage});

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: baseImage,
      filterQuality: FilterQuality.none,
      fit: BoxFit.contain,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return baseImage != oldDelegate.baseImage;
  }
}