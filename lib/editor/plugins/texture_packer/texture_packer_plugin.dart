import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/command/command_models.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/cache/type_adapters.dart';
import 'package:machine/editor/models/editor_command_context.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/editor/models/editor_plugin_models.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/plugins/tiled_editor/tiled_editor_plugin.dart'; // Re-using a CommandPosition
import 'texture_packer_command_context.dart';
import 'texture_packer_editor_models.dart';
import 'texture_packer_editor_widget.dart';
import 'texture_packer_models.dart';
import 'widgets/slicing_properties_dialog.dart';

class TexturePackerPlugin extends EditorPlugin {
  static const textureFloatingToolbar = CommandPosition(
    id: 'texture_floating_toolbar',
    label: 'Texture Floating Toolbar',
    icon: Icons.grid_on_outlined,
  );

  
  @override
  String get id => 'com.machine.texture_packer';

  @override
  String get name => 'Texture Packer';

  @override
  Widget get icon => const Icon(Icons.grid_view);

  @override
  int get priority => 5; // Same as Tiled Editor

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.toLowerCase().endsWith('.tpacker');
  }

  @override
  final PluginSettings? settings = PluginSettings();
  @override
    Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) => const SizedBox.shrink();


  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    final content = (initData.initialContent as EditorContentString).content;
    
    // Parse the .tpacker file content into our project data model.
    final TexturePackerProject projectState;
    if (content.trim().isEmpty) {
      projectState = TexturePackerProject.fresh();
    } else {
      projectState = TexturePackerProject.fromJson(jsonDecode(content));
    }

    return TexturePackerTab(
      plugin: this,
      initialProjectState: projectState,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return TexturePackerEditorWidget(
      key: (tab as TexturePackerTab).editorKey,
      tab: tab,
    );
  }
  
  TexturePackerEditorWidgetState? _getEditorState(WidgetRef ref) {
    final tab =
        ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (tab is TexturePackerTab) {
      return tab.editorKey.currentState as TexturePackerEditorWidgetState?;
    }
    return null;
  }
  
  @override
  List<CommandPosition> getCommandPositions() => [
    textureFloatingToolbar // Re-using the floating toolbar position
  ];

  @override
  List<Command> getCommands() {
    return [
      // Mode Switching Commands
      BaseCommand(
        id: 'packer_toggle_pan_zoom_mode',
        label: 'Pan/Zoom',
        icon: Consumer(builder: (context, ref, _) {
          final ctx = ref.watch(activeCommandContextProvider);
          final isActive = ctx is TexturePackerCommandContext && ctx.mode == TexturePackerMode.panZoom;
          return Icon(Icons.pan_tool_outlined, color: isActive ? Theme.of(context).colorScheme.primary : null);
        }),
        defaultPositions: [textureFloatingToolbar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.setMode(TexturePackerMode.panZoom),
      ),
      BaseCommand(
        id: 'packer_toggle_slicing_mode',
        label: 'Slice & Select',
        icon: Consumer(builder: (context, ref, _) {
          final ctx = ref.watch(activeCommandContextProvider);
          final isActive = ctx is TexturePackerCommandContext && ctx.mode == TexturePackerMode.slicing;
          return Icon(Icons.select_all_outlined, color: isActive ? Theme.of(context).colorScheme.primary : null);
        }),
        defaultPositions: [textureFloatingToolbar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.setMode(TexturePackerMode.slicing),
      ),
      
      // Panel Toggle Commands
      BaseCommand(
        id: 'packer_toggle_sources_panel',
        label: 'Source Images',
        icon: Consumer(builder: (context, ref, _) {
          final ctx = ref.watch(activeCommandContextProvider);
          final isActive = ctx is TexturePackerCommandContext && ctx.isSourceImagesPanelVisible;
          return Icon(Icons.photo_library_outlined, color: isActive ? Theme.of(context).colorScheme.primary : null);
        }),
        defaultPositions: [AppCommandPositions.pluginToolbar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.toggleSourceImagesPanel(),
      ),
      BaseCommand(
        id: 'packer_toggle_hierarchy_panel',
        label: 'Hierarchy',
        icon: Consumer(builder: (context, ref, _) {
          final ctx = ref.watch(activeCommandContextProvider);
          final isActive = ctx is TexturePackerCommandContext && ctx.isHierarchyPanelVisible;
          return Icon(Icons.account_tree_outlined, color: isActive ? Theme.of(context).colorScheme.primary : null);
        }),
        defaultPositions: [AppCommandPositions.pluginToolbar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.toggleHierarchyPanel(),
      ),

      // Other Commands
      BaseCommand(
        id: 'packer_edit_slicing_properties',
        label: 'Slicing Properties',
        icon: const Icon(Icons.tune_outlined),
        defaultPositions: [AppCommandPositions.pluginToolbar],
        sourcePlugin: id,
        execute: (ref) async {
          final editor = _getEditorState(ref);
          if (editor != null) {
            await SlicingPropertiesDialog.show(editor.context, editor.widget.tab.id);
          }
        },
      ),
    ];
  }
  
  // --- Other optional plugin overrides can go here ---

  @override
  String? get hotStateDtoType => null; // Not implemented yet

  @override
  Type? get hotStateDtoRuntimeType => null; // Not implemented yet

  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => null; // Not implemented yet
}