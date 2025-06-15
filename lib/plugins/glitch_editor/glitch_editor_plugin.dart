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

// Private "hot" state for each tab.
class _GlitchTabState {
  ui.Image image;
  final ui.Image originalImage;
  List<ui.Image> undoStack = [];
  List<ui.Image> redoStack = [];

  _GlitchTabState({required this.image, required this.originalImage});
}

class GlitchEditorPlugin implements EditorPlugin {
  final Map<String, _GlitchTabState> _tabStates = {};
  final Random _random = Random();

  // A local provider for the brush settings, owned by the plugin.
  final brushSettingsProvider = StateProvider((ref) => GlitchBrushSettings());

  @override
  String get name => 'Glitch Editor';
  @override
  Widget get icon => const Icon(Icons.broken_image_outlined);
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
  Future<EditorTab> createTab(DocumentFile file, String content) async {
    // content is raw bytes for an image, so we ignore it and read the file.
    final handler = ref.read(appNotifierProvider).value!.currentProject!.fileHandler;
    final fileBytes = await handler.readFileAsBytes(file.uri);
    final codec = await ui.instantiateImageCodec(fileBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    _tabStates[file.uri] = _GlitchTabState(image: image, originalImage: image);
    return GlitchEditorTab(file: file, plugin: this);
  }

  @override
  Future<EditorTab> createTabFromSerialization(
      Map<String, dynamic> tabJson, FileHandler fileHandler) async {
    final file = await fileHandler.getFileMetadata(tabJson['fileUri']);
    if (file == null) throw Exception('File not found: ${tabJson['fileUri']}');
    // For images, we don't restore state, just re-open the original file.
    return createTab(file, '');
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
    state?.undoStack.forEach((img) => img.dispose());
    state?.redoStack.forEach((img) => img.dispose());
  }

  // --- State Management API for the UI ---

  ui.Image? getImageForTab(GlitchEditorTab tab) => _tabStates[tab.file.uri]?.image;

  void updateBrushSettings(GlitchBrushSettings settings) {
      final notifier = ProviderScope.containerOf(this as GlitchEditorPlugin).read(brushSettingsProvider.notifier);
      notifier.state = settings;
  }

  void beginGlitchStroke(GlitchEditorTab tab) {
    final state = _tabStates[tab.file.uri];
    if (state == null) return;
    state.undoStack.add(state.image.clone());
    state.redoStack.clear();
  }
  
  ui.Image? applyGlitchEffect({required GlitchEditorTab tab, required Offset position}) {
    final state = _tabStates[tab.file.uri];
    final settings = ProviderScope.containerOf(this as GlitchEditorPlugin).read(brushSettingsProvider);
    if (state == null) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Draw the current image as the base
    canvas.drawImage(state.image, Offset.zero, Paint());

    // Apply the glitch effect
    switch (settings.type) {
      case GlitchBrushType.scatter:
        _applyScatter(canvas, state.image, position, settings);
        break;
      case GlitchBrushType.repeater:
         _applyRepeater(canvas, state.image, position, settings);
        break;
    }

    final picture = recorder.endRecording();
    // We update the state in-place for performance while dragging.
    state.image = picture.toImageSync(state.image.width, state.image.height);
    picture.dispose();
    return state.image;
  }
  
  void endGlitchStroke(GlitchEditorTab tab, WidgetRef ref) {
      final isDirty = _tabStates[tab.file.uri]?.undoStack.isNotEmpty ?? false;
      if (isDirty) {
          ref.read(tabStateProvider.notifier).markDirty(tab.file.uri);
      }
  }

  // --- Glitch Algorithms ---

  void _applyScatter(Canvas canvas, ui.Image source, Offset pos, GlitchBrushSettings settings) {
    final radius = settings.radius;
    final count = (radius * radius * settings.density * 0.1).toInt();
    for (int i = 0; i < count; i++) {
        final srcX = pos.dx + _random.nextDouble() * radius * 2 - radius;
        final srcY = pos.dy + _random.nextDouble() * radius * 2 - radius;
        final dstX = pos.dx + _random.nextDouble() * radius * 2 - radius;
        final dstY = pos.dy + _random.nextDouble() * radius * 2 - radius;
        final size = 2 + _random.nextDouble() * 4;

        final srcRect = Rect.fromLTWH(srcX, srcY, size, size);
        final dstRect = Rect.fromLTWH(dstX, dstY, size, size);

        canvas.drawImageRect(source, srcRect, dstRect, Paint());
    }
  }

  void _applyRepeater(Canvas canvas, ui.Image source, Offset pos, GlitchBrushSettings settings) {
      final radius = settings.radius;
      final srcRect = Rect.fromCenter(center: pos, width: radius, height: radius);
      
      for(int i = -5; i < 5; i++) {
          if (i == 0) continue;
          final offset = Offset(i * settings.repeatSpacing.toDouble(), i * settings.repeatSpacing.toDouble());
          canvas.drawImageRect(source, srcRect, srcRect.shift(offset), Paint()..blendMode = BlendMode.difference);
      }
  }

  // --- Command Implementations ---

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
        
        // Reset state after saving
        state.originalImage.dispose(); // dispose old original
        state.undoStack.forEach((img) => img.dispose());
        state.redoStack.forEach((img) => img.dispose());
        _tabStates[tab.file.uri] = _GlitchTabState(image: state.image.clone(), originalImage: state.image.clone());
      },
      canExecute: (ref) => ref.watch(tabStateProvider)[ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab?.file.uri] ?? false,
    ),
    BaseCommand(id: 'undo', label: 'Undo Glitch', icon: const Icon(Icons.undo), defaultPosition: CommandPosition.pluginToolbar, sourcePlugin: runtimeType.toString(),
      execute: (ref) {
        final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as GlitchEditorTab?;
        final state = tab != null ? _tabStates[tab.file.uri] : null;
        if (state == null || state.undoStack.isEmpty) return;

        state.redoStack.add(state.image);
        state.image = state.undoStack.removeLast();
        
        final isDirty = state.undoStack.isNotEmpty;
        if (!isDirty) ref.read(tabStateProvider.notifier).markClean(tab!.file.uri);
        
        ref.read(appNotifierProvider.notifier).updateCurrentTab(tab!.copyWith());
      },
      canExecute: (ref) => _tabStates[ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab?.file.uri]?.undoStack.isNotEmpty ?? false,
    ),
     BaseCommand(id: 'redo', label: 'Redo Glitch', icon: const Icon(Icons.redo), defaultPosition: CommandPosition.pluginToolbar, sourcePlugin: runtimeType.toString(),
      execute: (ref) {
        final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab as GlitchEditorTab?;
        final state = tab != null ? _tabStates[tab.file.uri] : null;
        if (state == null || state.redoStack.isEmpty) return;

        state.undoStack.add(state.image);
        state.image = state.redoStack.removeLast();

        ref.read(tabStateProvider.notifier).markDirty(tab!.file.uri);
        ref.read(appNotifierProvider.notifier).updateCurrentTab(tab.copyWith());
      },
      canExecute: (ref) => _tabStates[ref.watch(appNotifierProvider).value?.currentProject?.session.currentTab?.file.uri]?.redoStack.isNotEmpty ?? false,
    ),
  ];
  
  // Stubs for other interface methods
  @override
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}
}

// Global ref for the plugin to access providers.
// This is a necessary evil when methods are called from outside the widget tree.
final _refProvider = Provider<Ref>((ref) => ref);
extension GlitchEditorPluginRef on GlitchEditorPlugin {
    Ref get ref => ProviderScope.containerOf(this as GlitchEditorPlugin).read(_refProvider);
}