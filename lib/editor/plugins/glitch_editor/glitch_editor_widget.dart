// lib/plugins/glitch_editor/glitch_editor_widget.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'glitch_editor_math.dart';
import 'glitch_editor_models.dart';
import 'glitch_editor_plugin.dart';
import '../../tab_state_manager.dart';

// The State class is now public to be accessible via the GlobalKey.
class GlitchEditorWidget extends ConsumerStatefulWidget {
  final GlitchEditorTab tab;
  final GlitchEditorPlugin plugin;

  const GlitchEditorWidget({
    // The key is the GlobalKey from the tab model, passed by the plugin.
    super.key,
    required this.tab,
    required this.plugin,
  });

  @override
  _GlitchEditorWidgetState createState() => _GlitchEditorWidgetState();
}

class _GlitchEditorWidgetState extends ConsumerState<GlitchEditorWidget> {
  // --- STATE ---
  // All "hot" state is now here, inside the widget's State object.
  ui.Image? _displayImage;
  ui.Image? _originalImage;
  ui.Image? _strokeSample;
  ui.Image? _repeaterSample;
  Rect? _repeaterSampleRect;
  Offset? _lastRepeaterPosition;
  List<Offset> _repeaterPath = [];

  final TransformationController _transformationController = TransformationController();
  List<Offset> _currentStrokePoints = [];
  GlitchBrushSettings? _liveBrushSettings;
  Offset _imageDisplayOffset = Offset.zero;
  double _imageScale = 1.0;

  bool _isLoading = true;

  // --- PUBLIC PROPERTIES (for the command system) ---
  bool get isDirty => ref.read(tabMetadataProvider)[widget.tab.file.uri]?.isDirty ?? false;

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

  // --- LOGIC AND METHODS (moved from plugin/external state) ---

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

  // --- Public API for Commands ---
  
  Future<void> save() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null || _displayImage == null) return;
    
    final byteData = await _displayImage!.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final editorService = ref.read(editorServiceProvider);
    final success = await editorService.saveCurrentTab(
      project,
      bytes: byteData.buffer.asUint8List(),
    );

    // If save was successful, update the "original" image for future resets.
    if (success && mounted) {
      _originalImage?.dispose();
      setState(() {
        _originalImage = _displayImage!.clone();
      });
    }
  }

  Future<void> saveAs() async {
    final editorService = ref.read(editorServiceProvider);
    await editorService.saveCurrentTabAs(byteDataProvider: () async {
      if (_displayImage == null) return null;
      final byteData = await _displayImage!.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    });
  }

  void resetImage() {
    if (_originalImage == null) return;
    setState(() {
      _displayImage?.dispose();
      _displayImage = _originalImage!.clone();
    });
    ref.read(editorServiceProvider).markCurrentTabClean();
  }

  // --- Interaction Handlers ---

  void _onInteractionStart(ScaleStartDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;
    _liveBrushSettings = ref.read(widget.plugin.brushSettingsProvider).copyWith();
    
    // Begin stroke logic
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
    final inverseViewerMatrix = Matrix4.tryInvert(_transformationController.value);
    if (inverseViewerMatrix == null) return;
    final localPoint = MatrixUtils.transformPoint(inverseViewerMatrix, details.localFocalPoint);
    final imagePoint = _convertToImageCoordinates(localPoint);
    setState(() {
      _currentStrokePoints.add(imagePoint);
    });
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final isZoomMode = ref.read(widget.plugin.isZoomModeProvider);
    if (isZoomMode) return;
    
    // Apply the full stroke
    if (_displayImage == null || _currentStrokePoints.isEmpty) return;

    final viewerScale = _transformationController.value.getMaxScaleOnAxis();
    final safeScale = viewerScale.isFinite ? viewerScale : 1.0;
    final combinedScale = _imageScale * safeScale;

    final baseImage = _displayImage!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(baseImage, Offset.zero, Paint());

    for (final point in _currentStrokePoints) {
      _applyEffectToCanvas(canvas, point, _liveBrushSettings!.copyWith(
        radius: _liveBrushSettings!.radius / combinedScale,
        minBlockSize: _liveBrushSettings!.minBlockSize / combinedScale,
        maxBlockSize: _liveBrushSettings!.maxBlockSize / combinedScale,
      ));
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

    ref.read(editorServiceProvider).markCurrentTabDirty();
  }

  void _applyEffectToCanvas(Canvas canvas, Offset pos, GlitchBrushSettings settings) {
    switch (settings.type) {
      case GlitchBrushType.scatter:
        _applyScatter(canvas, _strokeSample!, pos, settings);
        break;
      case GlitchBrushType.repeater:
        _applyRepeater(canvas, pos, settings);
        break;
      case GlitchBrushType.heal:
        _applyHeal(canvas, pos, settings);
        break;
    }
  }

  // --- Glitch Logic (all private now) ---
  // ... (All the private _applyScatter, _applyRepeater, _applyHeal, etc. methods
  // would be moved from the old plugin file into here, unchanged.)

  void _applyScatter(
    Canvas canvas,
    ui.Image source,
    Offset pos,
    GlitchBrushSettings settings,
  ) {
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
  
  void _applyRepeater(
    Canvas canvas,
    GlitchTabState state,
    Offset pos,
    GlitchBrushSettings settings,
  ) {
    final radius = settings.radius * 500;
    final spacing = (settings.frequency * radius * 2).clamp(5.0, 200.0);
    if (state.repeaterSample == null) {
      _createRepeaterSample(state, pos, settings);
      state.lastRepeaterPosition = pos;
      state.repeaterPath.add(pos);
      _drawRepeaterSample(canvas, state, pos);
      return;
    }
    state.repeaterPath.add(pos);
    if (state.repeaterPath.length > 1) {
      final currentSegment = state.repeaterPath.sublist(
        state.repeaterPath.length - 2,
      );
      final start = currentSegment[0];
      final end = currentSegment[1];
      final direction = (end - start);
      final distance = direction.distance;
      if (distance > 0) {
        final stepVector = direction / distance;
        double accumulatedDistance = 0;
        int stepCount = 0;
        var currentDrawPos = state.lastRepeaterPosition!;
        while (accumulatedDistance < distance) {
          final nextDrawDistance = min(spacing, distance - accumulatedDistance);
          currentDrawPos += stepVector * nextDrawDistance;
          accumulatedDistance += nextDrawDistance;
          if (accumulatedDistance >= spacing || stepCount == 0) {
            _drawRepeaterSample(canvas, state, currentDrawPos);
          }
          stepCount++;
        }
        state.lastRepeaterPosition = currentDrawPos;
      }
    }
  }
  
  void _createRepeaterSample(
    GlitchTabState state,
    Offset pos,
    GlitchBrushSettings settings,
  ) {
    final radius = settings.radius * 500;
    state.repeaterSampleRect =
        settings.shape == GlitchBrushShape.circle
            ? Rect.fromCircle(center: pos, radius: radius / 2)
            : Rect.fromCenter(center: pos, width: radius, height: radius);
    state.repeaterSampleRect = Rect.fromLTRB(
      state.repeaterSampleRect!.left.clamp(0, state.strokeSample!.width.toDouble()),
      state.repeaterSampleRect!.top.clamp(0, state.strokeSample!.height.toDouble()),
      state.repeaterSampleRect!.right.clamp(0, state.strokeSample!.width.toDouble()),
      state.repeaterSampleRect!.bottom.clamp(0, state.strokeSample!.height.toDouble()),
    );
    final sampleRecorder = ui.PictureRecorder();
    final sampleCanvas = Canvas(sampleRecorder);
    sampleCanvas.drawImageRect(
      state.strokeSample!,
      state.repeaterSampleRect!,
      Rect.fromLTWH(0, 0, state.repeaterSampleRect!.width, state.repeaterSampleRect!.height),
      Paint(),
    );
    final samplePicture = sampleRecorder.endRecording();
    state.repeaterSample = samplePicture.toImageSync(
      state.repeaterSampleRect!.width.toInt(),
      state.repeaterSampleRect!.height.toInt(),
    );
    samplePicture.dispose();
  }

  void _drawRepeaterSample(Canvas canvas, GlitchTabState state, Offset pos) {
    final destRect = Rect.fromCenter(
      center: pos,
      width: state.repeaterSampleRect!.width,
      height: state.repeaterSampleRect!.height,
    );
    canvas.drawImageRect(
      state.repeaterSample!,
      Rect.fromLTWH(0, 0, state.repeaterSample!.width.toDouble(), state.repeaterSample!.height.toDouble()),
      destRect,
      Paint()..blendMode = BlendMode.srcOver,
    );
  }
  
  void _applyHeal(
    Canvas canvas,
    GlitchTabState state,
    Offset pos,
    GlitchBrushSettings settings,
  ) {
    final radius = settings.radius * 500;
    final sourceRect =
        settings.shape == GlitchBrushShape.circle
            ? Rect.fromCircle(center: pos, radius: radius / 2)
            : Rect.fromCenter(center: pos, width: radius, height: radius);
    final clampedSourceRect = Rect.fromLTRB(
      sourceRect.left.clamp(0, state.originalImage.width.toDouble()),
      sourceRect.top.clamp(0, state.originalImage.height.toDouble()),
      sourceRect.right.clamp(0, state.originalImage.width.toDouble()),
      sourceRect.bottom.clamp(0, state.originalImage.height.toDouble()),
    );
    canvas.drawImageRect(
      state.originalImage,
      clampedSourceRect,
      clampedSourceRect,
      Paint(),
    );
  }
  Offset _convertToImageCoordinates(Offset widgetPoint) {
    final adjustedPoint = widgetPoint - _imageDisplayOffset;
    return Offset(adjustedPoint.dx / _imageScale, adjustedPoint.dy / _imageScale);
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
            if (_displayImage != null)
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