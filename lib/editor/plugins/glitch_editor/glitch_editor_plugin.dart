// lib/plugins/glitch_editor/glitch_editor_plugin.dart
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../command/command_widgets.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../editor_tab_models.dart';
import '../plugin_models.dart';
import 'glitch_editor_models.dart';
import 'glitch_editor_widget.dart';
import 'glitch_toolbar.dart';
import '../../services/editor_service.dart';
import '../../tab_state_manager.dart'; // This import is now correct

class GlitchTabState implements TabState {
  ui.Image image;
  final ui.Image originalImage;
  ui.Image? strokeSample;
  ui.Image? repeaterSample;
  Rect? repeaterSampleRect;
  Offset? lastRepeaterPosition;
  List<Offset> repeaterPath = [];

  GlitchTabState({required this.image, required this.originalImage});

  void dispose() {
    image.dispose();
    originalImage.dispose();
    strokeSample?.dispose();
    repeaterSample?.dispose();
  }
}

class GlitchEditorPlugin implements EditorPlugin {
  final Random _random = Random();
  final brushSettingsProvider = StateProvider((ref) => GlitchBrushSettings());
  final isZoomModeProvider = StateProvider((ref) => false);
  final isSlidingProvider = StateProvider((ref) => false);

  @override
  String get name => 'Glitch Editor';
  @override
  Widget get icon => const Icon(Icons.broken_image_outlined);
  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.bytes;
  @override
  final PluginSettings? settings = null;
  @override
  Widget buildSettingsUI(PluginSettings settings) => const SizedBox.shrink();

  @override
  bool supportsFile(DocumentFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    return ['png', 'jpg', 'jpeg', 'bmp', 'webp'].contains(ext);
  }
  
  GlitchTabState? _getTabState(WidgetRef ref, EditorTab tab) {
    return ref.read(tabStateManagerProvider.notifier).getState(tab.file.uri);
  }

  @override
  Future<TabState> createTabState(EditorTab tab, dynamic data) async {
    // REFACTOR: Use the passed-in data to create the state.
    final Uint8List fileBytes = data as Uint8List;
    final codec = await ui.instantiateImageCodec(fileBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    return GlitchTabState(image: image, originalImage: image.clone());
  }

  @override
  void disposeTabState(TabState state) {
    (state as GlitchTabState).dispose();
  }

  @override
  Future<void> dispose() async {}

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];

  @override
  Future<EditorTab> createTab(DocumentFile file, dynamic data) async {
    return GlitchEditorTab(file: file, plugin: this);
  }

  @override
  Future<EditorTab> createTabFromSerialization(
    Map<String, dynamic> tabJson,
    FileHandler fileHandler,
  ) async {
    final file = await fileHandler.getFileMetadata(tabJson['fileUri']);
    if (file == null) throw Exception('File not found: ${tabJson['fileUri']}');
    final fileBytes = await fileHandler.readFileAsBytes(file.uri);
    return createTab(file, fileBytes);
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    return GlitchEditorWidget(tab: tab as GlitchEditorTab, plugin: this);
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    // REFACTOR: Return the correct toolbar widget.
    return const BottomToolbar();
  }

  @override
  void disposeTab(EditorTab tab) {}

  ui.Image? getImageForTab(WidgetRef ref, GlitchEditorTab tab) =>
      _getTabState(ref, tab)?.image;

  void updateBrushSettings(GlitchBrushSettings settings, WidgetRef ref) {
    ref.read(brushSettingsProvider.notifier).state = settings;
  }
  
  // REFACTOR: Pass ref from the widget to the plugin method.
  void beginGlitchStroke(WidgetRef ref, GlitchEditorTab tab) {
    final state = _getTabState(ref, tab);
    if (state == null) return;
    state.strokeSample?.dispose();
    state.repeaterSample?.dispose();
    state.strokeSample = state.image.clone();
    state.repeaterSample = null;
    state.repeaterSampleRect = null;
    state.lastRepeaterPosition = null;
    state.repeaterPath = [];
  }
  
  ui.Image? applyGlitchStroke({
    required GlitchEditorTab tab,
    required List<Offset> points,
    required GlitchBrushSettings settings,
    required WidgetRef ref,
  }) {
    final state = _getTabState(ref, tab);
    if (state == null || points.isEmpty) return null;
    final baseImage = state.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(baseImage, Offset.zero, Paint());
    for (final point in points) {
      _applyEffectToCanvas(canvas, point, settings, state);
    }
    final picture = recorder.endRecording();
    final newImage = picture.toImageSync(baseImage.width, baseImage.height);
    picture.dispose();
    final oldImage = state.image;
    state.image = newImage;
    oldImage.dispose();
    state.strokeSample?.dispose();
    state.strokeSample = null;
    ref.read(editorServiceProvider).markCurrentTabDirty();
    return newImage;
  }
  
  // REFACTOR: Method signature now uses GlitchTabState
  void _applyEffectToCanvas(
    Canvas canvas,
    Offset pos,
    GlitchBrushSettings settings,
    GlitchTabState state,
  ) {
    switch (settings.type) {
      case GlitchBrushType.scatter:
        _applyScatter(canvas, state.strokeSample!, pos, settings);
        break;
      case GlitchBrushType.repeater:
        _applyRepeater(canvas, state, pos, settings);
        break;
      case GlitchBrushType.heal:
        _applyHeal(canvas, state, pos, settings);
        break;
    }
  }

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

  @override
  List<Command> getCommands() => [
        BaseCommand(
          id: 'save',
          label: 'Save Image',
          icon: const Icon(Icons.save),
          defaultPosition: CommandPosition.appBar,
          sourcePlugin: runtimeType.toString(),
          execute: (ref) async {
            final project = ref.read(appNotifierProvider).value?.currentProject;
            final tab = project?.session.currentTab as GlitchEditorTab?;
            if (project == null || tab == null) return;
            
            final state = _getTabState(ref, tab);
            if (state == null) return;
            
            final byteData = await state.image.toByteData(format: ui.ImageByteFormat.png);
            if (byteData == null) return;

            // FIX: This call to EditorService is already correct.
            final editorService = ref.read(editorServiceProvider);
            final success = await editorService.saveCurrentTab(
              project,
              bytes: byteData.buffer.asUint8List(),
            );

            if (success) {
              state.originalImage.dispose();
              final newState = GlitchTabState(
                  image: state.image.clone(),
                  originalImage: state.image.clone());
              ref.read(tabStateManagerProvider.notifier).addState(tab.file.uri, newState);
              state.dispose();
            }
          },
          canExecute: (ref) => ref.watch(tabMetadataProvider.select(
            (s) => s[ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab?.file.uri]?.isDirty ?? false
          )),
        ),
        BaseCommand(
          id: 'save_as',
          label: 'Save As...',
          icon: const Icon(Icons.save_as),
          defaultPosition: CommandPosition.appBar,
          sourcePlugin: runtimeType.toString(),
          execute: (ref) async {
            // FIX: Call the correct service method.
            await ref.read(editorServiceProvider).saveCurrentTabAs(byteDataProvider: () async {
              final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as GlitchEditorTab?;
              if (tab == null) return null;
              final state = _getTabState(ref, tab);
              if (state == null) return null;
              final byteData = await state.image.toByteData(format: ui.ImageByteFormat.png);
              return byteData?.buffer.asUint8List();
            });
          },
          canExecute: (ref) =>
              ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab is GlitchEditorTab,
        ),
        BaseCommand(
          id: 'reset',
          label: 'Reset',
          icon: const Icon(Icons.refresh),
          defaultPosition: CommandPosition.pluginToolbar,
          sourcePlugin: runtimeType.toString(),
          execute: (ref) async {
            final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as GlitchEditorTab?;
            if (tab == null) return;
            final state = _getTabState(ref, tab);
            if (state == null) return;
            state.image.dispose();
            state.image = state.originalImage.clone();
            
            // FIX: Call the correct service method.
            ref.read(editorServiceProvider).markCurrentTabClean();
            // The `updateCurrentTab` call is correctly removed, as the widget will react to the state change.
          },
          canExecute: (ref) => ref.watch(tabMetadataProvider.select(
            (s) => s[ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab?.file.uri]?.isDirty ?? false
          )),
        ),
        // ... zoom_mode command ...
        BaseCommand(
          id: 'toggle_brush_settings',
          label: 'Brush Settings',
          icon: const Icon(Icons.brush),
          defaultPosition: CommandPosition.pluginToolbar,
          sourcePlugin: runtimeType.toString(),
          // FIX: Call the correct service method.
          execute: (ref) async => ref
              .read(editorServiceProvider)
              .setBottomToolbarOverride(GlitchToolbar(plugin: this)),
        ),
      ];

  @override
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}
}