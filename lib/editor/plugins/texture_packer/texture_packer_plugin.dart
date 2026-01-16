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
import 'texture_packer_command_context.dart';
import 'texture_packer_editor_models.dart';
import 'texture_packer_editor_widget.dart';
import 'texture_packer_models.dart';
import 'widgets/slicing_properties_dialog.dart';
import '../../../command/command_widgets.dart';
import 'widgets/texture_packer_settings_widget.dart';
import 'texture_packer_settings.dart';
import 'texture_packer_loader.dart'; // Import the new file

class TexturePackerPlugin extends EditorPlugin {
  // --- COMMAND SYSTEM REFACTOR ---
  // Define a unique CommandPosition for this plugin's floating toolbar.
  static const textureFloatingToolbar = CommandPosition(
    id: 'com.machine.texture_packer.floating_toolbar',
    label: 'Texture Packer Floating Toolbar',
    icon: Icons.grid_on_outlined,
  );
  // --- END REFACTOR ---
  
  @override
  String get id => 'com.machine.texture_packer';

  @override
  String get name => 'Texture Packer';

  @override
  Widget get icon => const Icon(Icons.grid_view);

  @override
  int get priority => 5;

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.toLowerCase().endsWith('.tpacker');
  }

  @override
  List<AssetLoader> get assetLoaders => [
    TexturePackerAssetLoader(),
  ];

  @override
  PluginSettings? get settings => TexturePackerSettings();

  @override
  Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) {
    if (settings is! TexturePackerSettings) return const SizedBox.shrink();
    return TexturePackerSettingsWidget(
      settings: settings,
      onChanged: (newSettings) => onChanged(newSettings),
    );
  }
  
  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    final content = (initData.initialContent as EditorContentString).content;
    
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
  
  @override
  Widget buildToolbar(WidgetRef ref) {
    return const BottomToolbar();
  }
  
  // --- COMMAND SYSTEM REFACTOR ---
  /// Helper method to get the active editor state for command execution.
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
    textureFloatingToolbar
  ];

  @override
  List<Command> getCommands() {
    return [
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
      // --- NEW: Preview Command ---
      BaseCommand(
        id: 'packer_toggle_preview_mode',
        label: 'Preview',
        icon: Consumer(builder: (context, ref, _) {
          final ctx = ref.watch(activeCommandContextProvider);
          final isActive = ctx is TexturePackerCommandContext && ctx.mode == TexturePackerMode.preview;
          return Icon(Icons.play_circle_outline, color: isActive ? Theme.of(context).colorScheme.primary : null);
        }),
        defaultPositions: [textureFloatingToolbar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.setMode(TexturePackerMode.preview),
      ),
      
      // --- Main Plugin Toolbar Commands ---
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
      BaseCommand(
        id: 'packer_edit_slicing_properties',
        label: 'Slicing Properties',
        icon: const Icon(Icons.tune_outlined),
        defaultPositions: [AppCommandPositions.pluginToolbar],
        sourcePlugin: id,
        execute: (ref) async {
          final editor = _getEditorState(ref);
          // We need the editor context to show the dialog.
          if (editor?.mounted == true) {
            await SlicingPropertiesDialog.show(editor!.context, editor.widget.tab.id, editor.notifier);
          }
        },
      ),
    ];
  }
  // --- END REFACTOR ---
  
  @override
  String? get hotStateDtoType => null;
  @override
  Type? get hotStateDtoRuntimeType => null;
  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => null;
}