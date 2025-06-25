// =========================================
// FILE: lib/editor/plugins/glitch_editor/glitch_editor_widget.dart
// =========================================

// lib/plugins/glitch_editor/glitch_editor_widget.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'glitch_editor_models.dart';
import 'glitch_editor_plugin.dart';
import 'glitch_toolbar.dart';
import '../../tab_state_manager.dart';
import 'glitch_editor_math.dart'; // ADDED MISSING IMPORT

class GlitchEditorWidget extends ConsumerStatefulWidget {
  final GlitchEditorTab tab;
  final GlitchEditorPlugin plugin;

  const GlitchEditorWidget({
    super.key,
    required this.tab,
    required this.plugin,
  });

  @override
  GlitchEditorWidgetState createState() => GlitchEditorWidgetState();
}

class GlitchEditorWidgetState extends ConsumerState<GlitchEditorWidget> {
  // --- STATE ---
  ui.Image? _displayImage;
  ui.Image? _originalImage;
  ui.Image? _strokeSample;
  ui.Image? _repeaterSample;
  Rect? _repeaterSampleRect;
  Offset? _lastRepeaterPosition;
  List<Offset> _repeaterPath = [];

  bool _isToolbarVisible = false;

  final TransformationController _transformationController =
      TransformationController();
  List<Offset> _currentStrokePoints = [];
  GlitchBrushSettings? _liveBrushSettings;
  Offset _imageDisplayOffset = Offset.zero;
  double _imageScale = 1.0;

  bool _isLoading = true;

  final Random _random = Random();

  // REFACTORED: The dirty flag is no longer managed here.
  // The command gets it directly from the metadata provider.
  // bool get isDirty => ...

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_updateImageDisplayParams);
    _loadImage();
  }

  @override
  void dispose() {
    _transformationController.removeListener(_updateImageDisplayParams);
    _transformationController.dispose();
    _displayImage?.dispose();
    _originalImage?.dispose();
    _strokeSample?.dispose();
    _repeaterSample?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.tab.initialImageData);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _displayImage = frame.image;
      _originalImage = frame.image.clone();
      _isLoading = false;
    });
  }

  void _updateImageDisplayParams() {
    if (_displayImage == null || !context.mounted || context.size == null)
      return;
    final imageSize = Size(
      _displayImage!.width.toDouble(),
      _displayImage!.height.toDouble(),
    );
    final widgetSize = context.size!;
    final fitted = applyBoxFit(BoxFit.contain, imageSize, widgetSize);
    final destinationSize = fitted.destination;
    _imageDisplayOffset = Offset(
      (widgetSize.width - destinationSize.width) / 2.0,
      (widgetSize.height - destinationSize.height) / 2.0,
    );
    _imageScale = destinationSize.width / imageSize.width;
  }

  // --- Public API for Commands ---

  Future<void> save() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null || _displayImage == null) return;

    final byteData = await _displayImage!.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) return;

    final editorService = ref.read(editorServiceProvider);
    // The service now handles getting the file from metadata to save to.
    final success = await editorService.saveCurrentTab(
      project,
      bytes: byteData.buffer.asUint8List(),
    );

    if (success && mounted) {
      updateOriginalImage();
    }
  }

  void toggleToolbar() {
    setState(() {
      _isToolbarVisible = !_isToolbarVisible;
    });
  }
  
  void updateOriginalImage() {
    if (_displayImage == null) return;
    setState(() {
      _originalImage?.dispose();
      _originalImage = _displayImage!.clone();
    });
  }

  Future<void> saveAs() async {
    final editorService = ref.read(editorServiceProvider);
    // The service handles the entire "Save As" flow.
    await editorService.saveCurrentTabAs(
      byteDataProvider: () async {
        if (_displayImage == null) return null;
        final byteData = await _displayImage!.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return byteData?.buffer.asUint8List();
      },
    );
  }

  void resetImage() {
    if (_originalImage == null) return;
    setState(() {
      _displayImage?.dispose();
      _displayImage = _originalImage!.clone();
    });
    // The service marks the tab as clean by its ID.
    ref.read(editorServiceProvider).markCurrentTabClean();
  }

  // --- Interaction Handlers ---

  void _onInteractionStart(ScaleStartDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;
    _liveBrushSettings =
        ref.read(widget.plugin.brushSettingsProvider).copyWith();

    _strokeSample?.dispose();
    _repeaterSample?.dispose();
    _strokeSample = _displayImage?.clone();
    _repeaterSample = null;
    _repeaterSampleRect = null;
    _lastRepeaterPosition = null;
    _repeaterPath = [];
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;
    final inverseViewerMatrix = Matrix4.tryInvert(
      _transformationController.value,
    );
    if (inverseViewerMatrix == null) return;
    final localPoint = MatrixUtils.transformPoint(
      inverseViewerMatrix,
      details.localFocalPoint,
    );
    final imagePoint = _convertToImageCoordinates(localPoint);
    setState(() {
      _currentStrokePoints.add(imagePoint);
    });
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;

    if (_displayImage == null || _currentStrokePoints.isEmpty) return;

    final viewerScale = _transformationController.value.getMaxScaleOnAxis();
    final safeScale = viewerScale.isFinite ? viewerScale : 1.0;
    final combinedScale = _imageScale * safeScale;

    final baseImage = _displayImage!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(baseImage, Offset.zero, Paint());

    for (final point in _currentStrokePoints) {
      _applyEffectToCanvas(
        canvas,
        point,
        _liveBrushSettings!.copyWith(
          radius: _liveBrushSettings!.radius / combinedScale,
          minBlockSize: _liveBrushSettings!.minBlockSize / combinedScale,
          maxBlockSize: _liveBrushSettings!.maxBlockSize / combinedScale,
        ),
      );
    }

    final picture = recorder.endRecording();
    final newImage = picture.toImageSync(baseImage.width, baseImage.height);
    picture.dispose();

    setState(() {
      _displayImage?.dispose();
      _displayImage = newImage;
      _strokeSample?.dispose();
      _strokeSample = null;
      _currentStrokePoints = [];
      _liveBrushSettings = null;
    });

    // The service marks the current tab as dirty by its ID.
    ref.read(editorServiceProvider).markCurrentTabDirty();
  }
  
  // ... (all glitch logic and build method are unchanged) ...
  void _applyEffectToCanvas(
    Canvas canvas,
    Offset pos,
    GlitchBrushSettings settings,
  ) {
    switch (settings.type) {
      case GlitchBrushType.scatter:
        _applyScatter(canvas, pos, settings);
        break;
      case GlitchBrushType.repeater:
        _applyRepeater(canvas, pos, settings);
        break;
      case GlitchBrushType.heal:
        _applyHeal(canvas, pos, settings);
        break;
    }
  }

  void _applyScatter(Canvas canvas, Offset pos, GlitchBrushSettings settings) {
    final source = _strokeSample;
    if (source == null) return;
    final radius = settings.radius * 500;
    final count = (settings.frequency * 20).toInt().clamp(1, 50);
    for (int i = 0; i < count; i++) {
      final srcX = pos.dx + _random.nextDouble() * radius - (radius / 2);
      final srcY = pos.dy + _random.nextDouble() * radius - (radius / 2);
      final dstX = pos.dx + _random.nextDouble() * radius - (radius / 2);
      final dstY = pos.dy + _random.nextDouble() * radius - (radius / 2);
      final size =
          settings.minBlockSize +
          _random.nextDouble() *
              (settings.maxBlockSize - settings.minBlockSize);
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(srcX, srcY, size, size),
        Rect.fromLTWH(dstX, dstY, size, size),
        Paint(),
      );
    }
  }

  void _applyRepeater(Canvas canvas, Offset pos, GlitchBrushSettings settings) {
    final radius = settings.radius * 500;
    final spacing = (settings.frequency * radius * 2).clamp(5.0, 200.0);
    if (_repeaterSample == null) {
      _createRepeaterSample(pos, settings);
      _lastRepeaterPosition = pos;
      _repeaterPath.add(pos);
      _drawRepeaterSample(canvas, pos);
      return;
    }
    _repeaterPath.add(pos);
    if (_repeaterPath.length > 1) {
      final currentSegment = _repeaterPath.sublist(_repeaterPath.length - 2);
      final start = currentSegment[0];
      final end = currentSegment[1];
      final direction = (end - start);
      final distance = direction.distance;
      if (distance > 0) {
        final stepVector = direction / distance;
        double accumulatedDistance = 0;
        int stepCount = 0;
        var currentDrawPos = _lastRepeaterPosition!;
        while (accumulatedDistance < distance) {
          final nextDrawDistance = min(spacing, distance - accumulatedDistance);
          currentDrawPos += stepVector * nextDrawDistance;
          accumulatedDistance += nextDrawDistance;
          if (accumulatedDistance >= spacing || stepCount == 0) {
            _drawRepeaterSample(canvas, currentDrawPos);
          }
          stepCount++;
        }
        _lastRepeaterPosition = currentDrawPos;
      }
    }
  }

  void _createRepeaterSample(Offset pos, GlitchBrushSettings settings) {
    if (_strokeSample == null) return;
    final radius = settings.radius * 500;
    _repeaterSampleRect =
        settings.shape == GlitchBrushShape.circle
            ? Rect.fromCircle(center: pos, radius: radius / 2)
            : Rect.fromCenter(center: pos, width: radius, height: radius);
    _repeaterSampleRect = Rect.fromLTRB(
      _repeaterSampleRect!.left.clamp(0, _strokeSample!.width.toDouble()),
      _repeaterSampleRect!.top.clamp(0, _strokeSample!.height.toDouble()),
      _repeaterSampleRect!.right.clamp(0, _strokeSample!.width.toDouble()),
      _repeaterSampleRect!.bottom.clamp(0, _strokeSample!.height.toDouble()),
    );
    final sampleRecorder = ui.PictureRecorder();
    final sampleCanvas = Canvas(sampleRecorder);
    sampleCanvas.drawImageRect(
      _strokeSample!,
      _repeaterSampleRect!,
      Rect.fromLTWH(
        0,
        0,
        _repeaterSampleRect!.width,
        _repeaterSampleRect!.height,
      ),
      Paint(),
    );
    final samplePicture = sampleRecorder.endRecording();
    _repeaterSample = samplePicture.toImageSync(
      _repeaterSampleRect!.width.toInt(),
      _repeaterSampleRect!.height.toInt(),
    );
    samplePicture.dispose();
  }

  void _drawRepeaterSample(Canvas canvas, Offset pos) {
    if (_repeaterSample == null || _repeaterSampleRect == null) return;
    final destRect = Rect.fromCenter(
      center: pos,
      width: _repeaterSampleRect!.width,
      height: _repeaterSampleRect!.height,
    );
    canvas.drawImageRect(
      _repeaterSample!,
      Rect.fromLTWH(
        0,
        0,
        _repeaterSample!.width.toDouble(),
        _repeaterSample!.height.toDouble(),
      ),
      destRect,
      Paint()..blendMode = BlendMode.srcOver,
    );
  }

  void _applyHeal(Canvas canvas, Offset pos, GlitchBrushSettings settings) {
    if (_originalImage == null) return;
    final radius = settings.radius * 500;
    final sourceRect =
        settings.shape == GlitchBrushShape.circle
            ? Rect.fromCircle(center: pos, radius: radius / 2)
            : Rect.fromCenter(center: pos, width: radius, height: radius);
    final clampedSourceRect = Rect.fromLTRB(
      sourceRect.left.clamp(0, _originalImage!.width.toDouble()),
      sourceRect.top.clamp(0, _originalImage!.height.toDouble()),
      sourceRect.right.clamp(0, _originalImage!.width.toDouble()),
      sourceRect.bottom.clamp(0, _originalImage!.height.toDouble()),
    );
    canvas.drawImageRect(
      _originalImage!,
      clampedSourceRect,
      clampedSourceRect,
      Paint(),
    );
  }

  Offset _convertToImageCoordinates(Offset widgetPoint) {
    final adjustedPoint = widgetPoint - _imageDisplayOffset;
    return Offset(
      adjustedPoint.dx / _imageScale,
      adjustedPoint.dy / _imageScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateImageDisplayParams();
    });

    final isZoomMode = ref.watch(widget.plugin.isZoomModeProvider);
    final isSliding = ref.watch(widget.plugin.isSlidingProvider);
    final brushSettings = ref.watch(widget.plugin.brushSettingsProvider);
    final screenWidth = MediaQuery.of(context).size.width;

    final editorContent = InteractiveViewer(
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
            if (_displayImage != null)
              CustomPaint(
                size: Size(
                  _displayImage!.width.toDouble(),
                  _displayImage!.height.toDouble(),
                ),
                painter: _ImagePainter(baseImage: _displayImage!),
              ),
            if (isSliding)
              IgnorePointer(
                child: _BrushPreview(
                  settings: brushSettings,
                  screenWidth: screenWidth,
                ),
              ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        editorContent,
        if (_isToolbarVisible)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: GlitchToolbar(
              plugin: widget.plugin,
              onClose: () => toggleToolbar(),
            ),
          ),
      ],
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
        shape:
            settings.shape == GlitchBrushShape.circle
                ? BoxShape.circle
                : BoxShape.rectangle,
        color: Colors.white.withOpacity(0.3),
        border: Border.all(color: Colors.white.withOpacity(0.7), width: 2),
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