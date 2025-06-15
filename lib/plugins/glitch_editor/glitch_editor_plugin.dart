// lib/plugins/glitch_editor/glitch_editor_plugin.dart
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../command/command_models.dart';
import '../../data/file_handler/file_handler.dart';
import '../../session/session_models.dart';
import '../../session/tab_state.dart';
import '../plugin_models.dart';
import 'glitch_editor_models.dart';
import 'glitch_editor_widget.dart';
import 'glitch_toolbar.dart';

// SIMPLIFIED: No more undo/redo stacks, just the current and original images.
class _GlitchTabState {
  ui.Image image;
  final ui.Image originalImage;

  _GlitchTabState({required this.image, required this.originalImage});
}

class GlitchEditorPlugin implements EditorPlugin {
  final Map<String, _GlitchTabState> _tabStates = {};
  final Random _random = Random();

  final brushSettingsProvider = StateProvider((ref) => GlitchBrushSettings());

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
    _tabStates[file.uri] = _GlitchTabState(image: image, originalImage: image.clone());
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
    return GlitchToolbar(plugin: this);
  }

  @override
  void disposeTab(EditorTab tab) {
    final state = _tabStates.remove(tab.file.uri);
    state?.image.dispose();
    state?.originalImage.dispose();
  }

  ui.Image? getImageForTab(GlitchEditorTab tab) => _tabStates[tab.file.uri]?.image;

  void updateBrushSettings(GlitchBrushSettings settings, WidgetRef ref) {
    ref.read(brushSettingsProvider.notifier).state = settings;
  }

  // This method now "bakes" the stroke into a new image.
  void applyGlitchStroke({
    required GlitchEditorTab tab,
    required List<Offset> points,
    required GlitchBrushSettings settings,
    required WidgetRef ref,
  }) {
    final state = _tabStates[tab.file.uri];
    if (state == null || points.isEmpty) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Use the current image in the state as the base for the new one.
    final baseImage = state.image;
    canvas.drawImage(baseImage, Offset.zero, Paint());

    for (final point in points) {
      switch (settings.type) {
        case GlitchBrushType.scatter:
          _applyScatter(canvas, baseImage, point, settings);
          break;
        case GlitchBrushType.repeater:
          _applyRepeater(canvas, baseImage, point, settings);
          break;
      }
    }
    
    final picture = recorder.endRecording();
    // This is the single expensive image creation operation.
    final newImage = picture.toImageSync(baseImage.width, baseImage.height);
    picture.dispose();
    
    // Update the state with the newly baked image.
    state.image = newImage;

    // Mark as dirty and notify the UI to update.
    ref.read(tabStateProvider.notifier).markDirty(tab.file.uri);
    ref.read(appNotifierProvider.notifier).updateCurrentTab(tab.copyWith());
  }

  // Private glitch algorithms remain the same.
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
    // NEW: Reset command instead of undo/redo.
    BaseCommand(id: 'reset', label: 'Reset', icon: const Icon(Icons.refresh), defaultPosition: CommandPosition.pluginToolbar, sourcePlugin: runtimeType.toString(),
      execute: (ref) async {
        final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as GlitchEditorTab?;
        if (tab == null) return;
        final state = _tabStates[tab.file.uri];
        if (state == null) return;

        // Restore the image from the pristine original.
        state.image = state.originalImage.clone();
        
        // Mark the tab as clean and update the UI.
        ref.read(tabStateProvider.notifier).markClean(tab.file.uri);
        ref.read(appNotifierProvider.notifier).updateCurrentTab(tab.copyWith());
      },
      canExecute: (ref) => ref.watch(tabStateProvider)[ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab?.file.uri] ?? false,
    ),
  ];
  
  @override
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}
}