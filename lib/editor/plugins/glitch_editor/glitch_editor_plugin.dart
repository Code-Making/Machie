// lib/plugins/glitch_editor/glitch_editor_plugin.dart
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
import '../../tab_state_manager.dart';

class GlitchEditorPlugin implements EditorPlugin {
  // These providers remain here as they control the plugin's UI, not its document state.
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
  Future<EditorTab> createTab(DocumentFile file, dynamic data) async {
    return GlitchEditorTab(file: file, plugin: this, initialImageData: data);
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
    final glitchTab = tab as GlitchEditorTab;
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

  GlitchEditorWidgetState? _getActiveEditorState(WidgetRef ref) {
    final tab = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab,
      ),
    );
    if (tab is! GlitchEditorTab) return null;
    return tab.editorKey.currentState as GlitchEditorWidgetState?;
  }

  @override
  List<Command> getCommands() => [
    BaseCommand(
      id: 'save',
      label: 'Save Image',
      icon: const Icon(Icons.save),
      defaultPosition: CommandPosition.appBar,
      sourcePlugin: runtimeType.toString(),
      // FIX: Use async closure for async method call
      execute: (ref) async => await _getActiveEditorState(ref)?.save(),
      canExecute: (ref) {
        ref.watch(tabMetadataProvider);
        return _getActiveEditorState(ref)?.isDirty ?? false;
      },
    ),
    BaseCommand(
      id: 'save_as',
      label: 'Save As...',
      icon: const Icon(Icons.save_as),
      defaultPosition: CommandPosition.appBar,
      sourcePlugin: runtimeType.toString(),
      // FIX: Use async closure for async method call
      execute: (ref) async => await _getActiveEditorState(ref)?.saveAs(),
      canExecute: (ref) => _getActiveEditorState(ref) != null,
    ),
    BaseCommand(
      id: 'reset',
      label: 'Reset',
      icon: const Icon(Icons.refresh),
      defaultPosition: CommandPosition.pluginToolbar,
      sourcePlugin: runtimeType.toString(),
      // FIX: This method is synchronous, no async needed.
      execute: (ref) async => _getActiveEditorState(ref)?.resetImage(),
      canExecute: (ref) {
        ref.watch(tabMetadataProvider);
        return _getActiveEditorState(ref)?.isDirty ?? false;
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
      defaultPosition: CommandPosition.pluginToolbar,
      sourcePlugin: runtimeType.toString(),
      // FIX: This method is synchronous, no async needed.
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
      defaultPosition: CommandPosition.pluginToolbar,
      sourcePlugin: runtimeType.toString(),
      // FIX: This method is synchronous, no async needed.
      execute: (ref) async => _getActiveEditorState(ref)?.toggleToolbar(),
    ),
  ];
}
