// lib/plugins/glitch_editor/glitch_editor_plugin.dart
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../command/command_models.dart';
import '../../command/command_widgets.dart';
import '../../data/file_handler/file_handler.dart';
import '../../session/session_models.dart';
import '../../session/tab_state.dart';
import '../plugin_models.dart';
import 'glitch_editor_models.dart';
import 'glitch_editor_widget.dart';
import 'glitch_toolbar.dart';

class _GlitchTabState {
  ui.Image image;
  final ui.Image originalImage;
  ui.Image? strokeSample; 

  _GlitchTabState({required this.image, required this.originalImage});
}

class GlitchEditorPlugin implements EditorPlugin {
  final Map<String, _GlitchTabState> _tabStates = {};
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

  @override
  Future<void> dispose() async {
    _tabStates.values.forEach((state) {
      state.image.dispose();
      state.originalImage.dispose();
      state.strokeSample?.dispose();
    });
    _tabStates.clear();
  }

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];

  @override
  Future<EditorTab> createTab(DocumentFile file, dynamic data) async {
    final Uint8List fileBytes = data as Uint8List;
    final codec = await ui.instantiateImageCodec(fileBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    _tabStates[file.uri] =
        _GlitchTabState(image: image, originalImage: image.clone());
    return GlitchEditorTab(file: file, plugin: this);
  }

  @override
  Future<EditorTab> createTabFromSerialization(
      Map<String, dynamic> tabJson, FileHandler fileHandler) async {
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
    return const BottomToolbar();
  }

  @override
  void disposeTab(EditorTab tab) {
    final state = _tabStates.remove(tab.file.uri);
    state?.image.dispose();
    state?.originalImage.dispose();
    state?.strokeSample?.dispose();
  }

  ui.Image? getImageForTab(GlitchEditorTab tab) =>
      _tabStates[tab.file.uri]?.image;

  void updateBrushSettings(GlitchBrushSettings settings, WidgetRef ref) {
    ref.read(brushSettingsProvider.notifier).state = settings;
  }

  void beginGlitchStroke(GlitchEditorTab tab) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;
    state.strokeSample = state.image.clone();
  }

  void applyGlitchStroke({
    required GlitchEditorTab tab,
    required List<Offset> points,
    required GlitchBrushSettings settings,
    required WidgetRef ref,
  }) {
    final state = _tabStates[tab.file.uri];
    if (state == null || points.isEmpty) return;

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

    ref.read(tabStateProvider.notifier).markDirty(tab.file.uri);
    ref.read(appNotifierProvider.notifier).updateCurrentTab(tab.copyWith());
  }
  
  void _applyEffectToCanvas(Canvas canvas, Offset pos, GlitchBrushSettings settings, _GlitchTabState state) {
      switch (settings.type) {
        case GlitchBrushType.scatter:
          _applyScatter(canvas, state.image, pos, settings);
          break;
        case GlitchBrushType.repeater:
          _applyRepeater(canvas, state.strokeSample!, pos, settings);
          break;
      }
  }

  void _applyScatter(Canvas canvas, ui.Image source, Offset pos, GlitchBrushSettings settings) {
      final radius = settings.radius * 500;
      final count = (settings.frequency * 20).toInt().clamp(1, 50);

      for (int i = 0; i < count; i++) {
        final srcX = pos.dx + _random.nextDouble() * radius - (radius / 2);
        final srcY = pos.dy + _random.nextDouble() * radius - (radius / 2);
        final dstX = pos.dx + _random.nextDouble() * radius - (radius / 2);
        final dstY = pos.dy + _random.nextDouble() * radius - (radius / 2);
        final size = settings.minBlockSize + _random.nextDouble() * (settings.maxBlockSize - settings.minBlockSize);
        canvas.drawImageRect(source, Rect.fromLTWH(srcX, srcY, size, size), Rect.fromLTWH(dstX, dstY, size, size), Paint());
      }
  }

  void _applyRepeater(Canvas canvas, ui.Image source, Offset pos, GlitchBrushSettings settings) {
      final radius = settings.radius * 500;
      final srcRect = settings.shape == GlitchBrushShape.circle
          ? Rect.fromCircle(center: pos, radius: radius / 2)
          : Rect.fromCenter(center: pos, width: radius, height: radius);
          
      final spacing = (settings.frequency * radius * 2).clamp(5.0, 200.0);
      for(int i = -3; i <= 3; i++) {
          if (i == 0) continue;
          final offset = Offset(i * spacing, 0);
          canvas.drawImageRect(source, srcRect, srcRect.shift(offset), Paint()..blendMode = BlendMode.difference);
      }
  }

  @override
  List<Command> getCommands() => [
  BaseCommand(id: 'save', label: 'Save Image', icon: const Icon(Icons.save), defaultPosition: CommandPosition.appBar, sourcePlugin: runtimeType.toString(),
      execute: (ref) async {
        final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as GlitchEditorTab?;
        if (tab == null) return;
        final state = _tabStates[tab.file.uri];
        if (state == null) return;
        final byteData = await state.image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;
        await ref.read(appNotifierProvider.notifier).saveCurrentTabAsBytes(byteData.buffer.asUint8List());
        state.originalImage.dispose();
        _tabStates[tab.file.uri] = _GlitchTabState(image: state.image.clone(), originalImage: state.image.clone());
      },
      canExecute: (ref) => ref.watch(tabStateProvider)[ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab?.file.uri] ?? false,
    ),
        // CORRECTED: The command now uses the `byteDataProvider` parameter.
    BaseCommand(id: 'save_as', label: 'Save As...', icon: const Icon(Icons.save_as), defaultPosition: CommandPosition.appBar, sourcePlugin: runtimeType.toString(),
      execute: (ref) async {
        await ref.read(appNotifierProvider.notifier).saveCurrentTabAs(
          byteDataProvider: () async {
            final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as GlitchEditorTab?;
            if (tab == null) return null;
            final state = _tabStates[tab.file.uri];
            if (state == null) return null;
            final byteData = await state.image.toByteData(format: ui.ImageByteFormat.png);
            return byteData?.buffer.asUint8List();
          }
        );
      },
      canExecute: (ref) => ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab is GlitchEditorTab,
    ),
    BaseCommand(id: 'reset', label: 'Reset', icon: const Icon(Icons.refresh), defaultPosition: CommandPosition.pluginToolbar, sourcePlugin: runtimeType.toString(),
      execute: (ref) async {
        final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as GlitchEditorTab?;
        if (tab == null) return;
        final state = _tabStates[tab.file.uri];
        if (state == null) return;
        state.image.dispose();
        state.image = state.originalImage.clone();
        ref.read(tabStateProvider.notifier).markClean(tab.file.uri);
        ref.read(appNotifierProvider.notifier).updateCurrentTab(tab.copyWith());
      },
      canExecute: (ref) => ref.watch(tabStateProvider)[ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab?.file.uri] ?? false,
    ),    
    BaseCommand(id: 'zoom_mode', label: 'Toggle Zoom', icon: const Icon(Icons.zoom_in), defaultPosition: CommandPosition.pluginToolbar, sourcePlugin: runtimeType.toString(),
      execute: (ref) async {
        final notifier = ref.read(isZoomModeProvider.notifier);
        notifier.state = !notifier.state;
      },
    ),
    BaseCommand(id: 'toggle_brush_settings', label: 'Brush Settings', icon: const Icon(Icons.brush), defaultPosition: CommandPosition.pluginToolbar, sourcePlugin: runtimeType.toString(),
      execute: (ref) async {
        ref.read(appNotifierProvider.notifier).setBottomToolbarOverride(GlitchToolbar(plugin: this));
      },
    ),
  ];

  @override
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}
}