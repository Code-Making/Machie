// =========================================
// FILE: lib/editor/plugins/glitch_editor/glitch_editor_plugin.dart
// =========================================

// lib/plugins/glitch_editor/glitch_editor_plugin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';
import 'dart:async';

import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../command/command_widgets.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../editor_tab_models.dart';
import '../../services/editor_service.dart';
import '../plugin_models.dart';
import 'glitch_editor_models.dart';
import 'glitch_editor_widget.dart';
import '../../tab_state_manager.dart';
import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../data/cache/type_adapters.dart';
import 'glitch_editor_hot_state_adapter.dart';
import 'glitch_editor_hot_state_dto.dart';
import 'package:machine/editor/plugins/editor_command_context.dart';
import 'glitch_editor_state.dart';

class GlitchEditorPlugin extends EditorPlugin {
  static const String pluginId = 'com.machine.glitch_editor';
  static const String hotStateId = 'com.machine.glitch_editor_state';

  final brushSettingsProvider = StateProvider((ref) => GlitchBrushSettings());
  final isZoomModeProvider = StateProvider((ref) => false);
  final isSlidingProvider = StateProvider((ref) => false);

  @override
  String get id => pluginId;
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
  Type? get hotStateDtoRuntimeType => GlitchEditorHotStateDto;

  @override
  int get priority => 1;

  @override
  bool supportsFile(DocumentFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    return ['png', 'jpg', 'jpeg', 'bmp', 'webp'].contains(ext);
  }

  /// This plugin handles binary data, so it does not participate in the
  /// string-based content check.
  @override
  bool canOpenFileContent(String content, DocumentFile file) {
    return false;
  }
  @override
  Future<void> dispose() async {}
  @override
  void disposeTab(EditorTab tab) {}
  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];
  @override
  void activateTab(EditorTab tab, Ref ref) {}
  @override
  void deactivateTab(EditorTab tab, Ref ref) {}
  @override
  List<CommandPosition> getCommandPositions() => [];

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    // The initial image is ALWAYS the data from disk.
    final byteContent = initData.initialContent as EditorContentBytes;
    final initialImageData = byteContent.content ?? Uint8List(0);
    final initialBaseContentHash = initData.baseContentHash;

    Uint8List? cachedImageData;

    if (initData.hotState is GlitchEditorHotStateDto) {
      final hotState = initData.hotState as GlitchEditorHotStateDto;
      // The cached image is stored separately.
      cachedImageData = hotState.imageData;
    }

    return GlitchEditorTab(
      plugin: this,
      initialImageData: initialImageData,
      cachedImageData: cachedImageData, // <-- Pass cached image separately
      initialBaseContentHash: initialBaseContentHash,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  // @override
  // Future<EditorTab> createTabFromSerialization(
  //   Map<String, dynamic> tabJson,
  //   FileHandler fileHandler,
  // ) async {
  //   final fileUri = tabJson['fileUri'];
  //   if (fileUri == null) throw Exception('File URI not found in serialization');
  //   final file = await fileHandler.getFileMetadata(fileUri);
  //   if (file == null) throw Exception('File not found: $fileUri');
  //   final fileBytes = await fileHandler.readFileAsBytes(file.uri);
  //   final initData = EditorInitData(byteData: fileBytes);
  //   return createTab(file, initData);
  // }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    // We must ensure the tab is the correct concrete type.
    final glitchTab = tab as GlitchEditorTab;

    // The key is now accessed directly from the correctly-typed tab model.
    return GlitchEditorWidget(
      key: glitchTab.editorKey,
      tab: glitchTab,
      plugin: this,
    );
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    return const BottomToolbar();
  }

  @override
  String get hotStateDtoType => hotStateId;

  @override
  TypeAdapter<TabHotStateDto> get hotStateAdapter =>
      GlitchEditorHotStateAdapter();

  @override
  Widget wrapCommandToolbar(Widget toolbar) {
    // This plugin doesn't need any special wrapping, so just return the toolbar.
    return toolbar;
  }

  /// Helper to get the active editor's state object.
  GlitchEditorWidgetState? _getEditorState(EditorTab tab) {
    if (tab.editorKey.currentState is GlitchEditorWidgetState) {
      return tab.editorKey.currentState as GlitchEditorWidgetState;
    }
    return null;
  }

  // @override
  // Future<TabHotStateDto?> serializeHotState(EditorTab tab) async {
  //   final editorState = _getEditorState(tab);
  //   if (editorState == null) return null;

  //   final stateMap = await editorState.getHotState();
  //   if (stateMap == null || stateMap['imageData'] == null) return null;

  //   return GlitchEditorHotStateDto(
  //     imageData: stateMap['imageData'] as Uint8List,
  //   );
  // }

  GlitchEditorWidgetState? _getActiveEditorState(WidgetRef ref) {
    final tab = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab));
    if (tab is! GlitchEditorTab) return null;
    return tab.editorKey.currentState as GlitchEditorWidgetState?;
  }

  @override
  List<Command> getAppCommands() => [];

  @override
  List<Command> getCommands() => [
    BaseCommand(
      id: 'save',
      label: 'Save Image',
      icon: const Icon(Icons.save),
      defaultPositions: [AppCommandPositions.appBar],
      sourcePlugin: id,
      execute: (ref) async => ref.read(editorServiceProvider).saveCurrentTab(),
      // MODIFIED: 'save' now watches the global TabMetadata provider.
      canExecute: (ref) {
        final currentTabId = ref.watch(appNotifierProvider.select(
          (s) => s.value?.currentProject?.session.currentTab?.id
        ));
        if (currentTabId == null) return false;
        final metadata = ref.watch(
          tabMetadataProvider.select((m) => m[currentTabId])
        );
        return metadata?.isDirty ?? false;
      },
    ),
    BaseCommand(
      id: 'reset',
      label: 'Reset',
      icon: const Icon(Icons.refresh),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.resetImage(),
      // MODIFIED: 'reset' also watches the global TabMetadata provider.
      canExecute: (ref) {
        final currentTabId = ref.watch(appNotifierProvider.select(
          (s) => s.value?.currentProject?.session.currentTab?.id
        ));
        if (currentTabId == null) return false;
        final metadata = ref.watch(
          tabMetadataProvider.select((m) => m[currentTabId])
        );
        return metadata?.isDirty ?? false;
      },
    ),
    BaseCommand(
      id: 'undo',
      label: 'Undo',
      icon: const Icon(Icons.undo),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.undo(),
      // MODIFIED: 'undo' now correctly watches the command context.
      canExecute: (ref) {
        final context = ref.watch(activeCommandContextProvider);
        return (context is GlitchEditorCommandContext) && context.canUndo;
      },
    ),
    BaseCommand(
      id: 'redo',
      label: 'Redo',
      icon: const Icon(Icons.redo),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.redo(),
      // MODIFIED: 'redo' now correctly watches the command context.
      canExecute: (ref) {
        final context = ref.watch(activeCommandContextProvider);
        return (context is GlitchEditorCommandContext) && context.canRedo;
      },
    ),
    BaseCommand(
      id: 'zoom_mode',
      label: 'Toggle Zoom',
      icon: Consumer(
        builder: (context, ref, _) {
          final isZoomOn = ref.watch(isZoomModeProvider);
          return Icon(isZoomOn ? Icons.zoom_out_map : Icons.zoom_in_map);
        },
      ),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute:
          (ref) async =>
              ref.read(isZoomModeProvider.notifier).update((state) => !state),
    ),
    BaseCommand(
      id: 'toggle_brush_settings',
      label: 'Brush Settings',
      icon: Consumer(
        builder: (context, ref, _) {
          final brushType = ref.watch(
            brushSettingsProvider.select((s) => s.type),
          );
          switch (brushType) {
            case GlitchBrushType.scatter:
              return const Icon(Icons.scatter_plot);
            case GlitchBrushType.repeater:
              return const Icon(Icons.line_axis);
            case GlitchBrushType.heal:
              return const Icon(Icons.healing);
          }
        },
      ),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.toggleToolbar(),
    ),
  ];
}
