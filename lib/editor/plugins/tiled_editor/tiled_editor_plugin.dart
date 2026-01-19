import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../models/editor_command_context.dart';
import '../../models/editor_plugin_models.dart';
import '../../models/editor_tab_models.dart';
import '../../services/editor_service.dart';
import '../../tab_metadata_notifier.dart';

import 'tiled_command_context.dart';
import 'tiled_editor_models.dart';
import 'tiled_editor_widget.dart';
import '../../../command/command_widgets.dart';
import 'tiled_paint_tools.dart';
import 'widgets/tiled_editor_settings_widget.dart';
import 'tiled_editor_settings_model.dart';
import 'widgets/export_dialog.dart';
import '../../../logs/logs_provider.dart';

class TiledEditorPlugin extends EditorPlugin {
  static const String pluginId = 'com.machine.tiled_editor';

  static const tiledFloatingToolbar = CommandPosition(
    id: 'tiled_floating_toolbar',
    label: 'Tiled Floating Toolbar',
    icon: Icons.grid_on_outlined,
  );

  static const paintToolsToolbar = CommandPosition(
    id: 'tiled_paint_tools',
    label: 'Tiled Paint Tools',
    icon: Icons.brush,
  );

  static const objectToolsToolbar = CommandPosition(
    id: 'tiled_object_tools',
    label: 'Tiled Object Tools',
    icon: Icons.category_outlined,
    // mandatoryCommands: ['tiled_object_tools_group'],
  );
  
  @override
  String get id => pluginId;

  @override
  String get name => 'Tiled Map Editor';

  @override
  Widget get icon => const Icon(Icons.grid_on_outlined);

  @override
  int get priority => 5;

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.toLowerCase().endsWith('.tmx');
  }
  
  @override
  PluginSettings? get settings => TiledEditorSettings();

  @override
  Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) =>
      TiledEditorSettingsWidget(settings: settings as TiledEditorSettings, onChanged: onChanged);

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    var tmxContent = (initData.initialContent as EditorContentString).content;
    var baseContentHash = initData.baseContentHash;
    if (tmxContent.trim().isEmpty) {
      tmxContent = _createDefaultTmx();
      baseContentHash = "new_map";
    }
    return TiledEditorTab(
      plugin: this,
      initialTmxContent: tmxContent,
      initialBaseContentHash: baseContentHash,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  String _createDefaultTmx() {
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" renderorder="right-down" width="10" height="10" tilewidth="16" tileheight="16" infinite="0" nextlayerid="2" nextobjectid="1">
</map>
''';
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return TiledEditorWidget(key: (tab as TiledEditorTab).editorKey, tab: tab);
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    return const BottomToolbar();
  }

  @override
  List<CommandPosition> getCommandPositions() =>
      [tiledFloatingToolbar, paintToolsToolbar, objectToolsToolbar];

  TiledEditorWidgetState? _getEditorState(WidgetRef ref) {
    final tab =
        ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (tab is TiledEditorTab) {
      return tab.editorKey.currentState as TiledEditorWidgetState?;
    }
    return null;
  }
  
    List<CommandGroup> getCommandGroups() {
    // This map is needed for the dynamic icon
    const objectToolIcons = {
      ObjectTool.select: Icons.touch_app_outlined,
      ObjectTool.move: Icons.open_with_outlined,
      ObjectTool.addRectangle: Icons.rectangle_outlined,
      ObjectTool.addEllipse: Icons.circle_outlined,
      ObjectTool.addPoint: Icons.add_location_alt_outlined,
      ObjectTool.addPolygon: Icons.pentagon_outlined,
      ObjectTool.addPolyline: Icons.polyline_outlined,
      ObjectTool.addText: Icons.text_fields_outlined,
      ObjectTool.addSprite: Icons.image_search, // <-- NEW ICON
    };

    return [
      CommandGroup(
        id: 'tiled_object_tools_group',
        label: 'Object Tools',
        // The commands will be displayed as icons only in the dropdown
        showLabels: false, 
        defaultPositions: [objectToolsToolbar], 
        // The icon is a Consumer that rebuilds when the active tool changes
        icon: Consumer(
          builder: (context, ref, _) {
            final ctx = ref.watch(activeCommandContextProvider);
            
            // Default icon if the Tiled editor isn't active
            var activeToolIcon = objectToolIcons[ObjectTool.select]!;

            if (ctx is TiledEditorCommandContext && ctx.mode == TiledEditorMode.object) {
              activeToolIcon = objectToolIcons[ctx.activeObjectTool] ?? activeToolIcon;
            }
            
            return Icon(activeToolIcon);
          },
        ),
        // This group will be placed in the toolbar by default
commandIds: ObjectTool.values
            .where((e) => e != ObjectTool.select)
            .where((e) => e != ObjectTool.move)
            .map((tool) => 'tiled_object_tool_${tool.name}')
            .toList(),
        isDeletable: false, // This is a plugin-defined group
        sourcePlugin: id,
      ),
    ];
  }

  @override
  List<Command> getCommands(){
    const objectToolIcons = {
      ObjectTool.select: Icons.touch_app_outlined,
      ObjectTool.move: Icons.open_with_outlined,
      ObjectTool.addRectangle: Icons.rectangle_outlined,
      ObjectTool.addEllipse: Icons.circle_outlined,
      ObjectTool.addPoint: Icons.add_location_alt_outlined,
      ObjectTool.addPolygon: Icons.pentagon_outlined,
      ObjectTool.addPolyline: Icons.polyline_outlined,
      ObjectTool.addText: Icons.text_fields_outlined,
       ObjectTool.addSprite: Icons.image_search, // <-- NEW ICON
    };
    
    const objectToolLabels = {
      ObjectTool.select: 'Select',
      ObjectTool.move: 'Move',
      ObjectTool.addRectangle: 'Add Rectangle',
      ObjectTool.addEllipse: 'Add Ellipse',
      ObjectTool.addPoint: 'Add Point',
      ObjectTool.addPolygon: 'Add Polygon',
      ObjectTool.addPolyline: 'Add Polyline',
      ObjectTool.addText: 'Add Text',      
      ObjectTool.addSprite: 'Add Sprite', // <-- NEW
    };


    final objectToolCommands = ObjectTool.values.map((tool) {
      return BaseCommand(
        id: 'tiled_object_tool_${tool.name}',
        label: objectToolLabels[tool] ?? tool.name,
        icon: Consumer(builder: (context, ref, _) {
          final ctx = ref.watch(activeCommandContextProvider);
          final isActive =
              ctx is TiledEditorCommandContext && ctx.activeObjectTool == tool;
          return Icon(objectToolIcons[tool],
              color: isActive ? Theme.of(context).colorScheme.primary : null);
        }),
        defaultPositions: [objectToolsToolbar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.setActiveObjectTool(tool),
          canExecute: (ref) {
            final ctx = ref.watch(activeCommandContextProvider);
            return ctx is TiledEditorCommandContext && ctx.mode == TiledEditorMode.object;
          },
      );
    }).toList();

    return [
      ...objectToolCommands,
        BaseCommand(
          id: 'tiled_toggle_pan_zoom_mode',
          label: 'Pan/Zoom',
          icon: Consumer(builder: (context, ref, _) {
            final ctx = ref.watch(activeCommandContextProvider);
            final isActive = ctx is TiledEditorCommandContext &&
                ctx.mode == TiledEditorMode.panZoom;
            return Icon(Icons.pan_tool_outlined,
                color:
                    isActive ? Theme.of(context).colorScheme.primary : null);
          }),
          defaultPositions: [tiledFloatingToolbar],
          sourcePlugin: id,
          execute: (ref) async =>
              _getEditorState(ref)?.setMode(TiledEditorMode.panZoom),
        ),
        BaseCommand(
          id: 'tiled_toggle_paint_mode',
          label: 'Paint Mode',
          icon: Consumer(builder: (context, ref, _) {
            final ctx = ref.watch(activeCommandContextProvider);
            final isActive = ctx is TiledEditorCommandContext &&
                ctx.mode == TiledEditorMode.paint;
            return Icon(Icons.brush,
                color:
                    isActive ? Theme.of(context).colorScheme.primary : null);
          }),
          defaultPositions: [tiledFloatingToolbar],
          sourcePlugin: id,
          execute: (ref) async =>
              _getEditorState(ref)?.setMode(TiledEditorMode.paint),
        ),
        BaseCommand(
          id: 'tiled_toggle_object_mode',
          label: 'Object Mode',
          icon: Consumer(builder: (context, ref, _) {
            final ctx = ref.watch(activeCommandContextProvider);
            final isActive = ctx is TiledEditorCommandContext &&
                ctx.mode == TiledEditorMode.object;
            return Icon(Icons.category_outlined,
                color:
                    isActive ? Theme.of(context).colorScheme.primary : null);
          }),
          defaultPositions: [tiledFloatingToolbar],
          sourcePlugin: id,
          execute: (ref) async =>
              _getEditorState(ref)?.setMode(TiledEditorMode.object),
        ),
        BaseCommand(
          id: 'tiled_undo',
          label: 'Undo',
          icon: const Icon(Icons.undo),
          defaultPositions: [AppCommandPositions.pluginToolbar],
          sourcePlugin: id,
          execute: (ref) async => _getEditorState(ref)?.undo(),
          canExecute: (ref) {
            final ctx = ref.watch(activeCommandContextProvider);
            return ctx is TiledEditorCommandContext && ctx.canUndo;
          },
        ),
        BaseCommand(
          id: 'tiled_redo',
          label: 'Redo',
          icon: const Icon(Icons.redo),
          defaultPositions: [AppCommandPositions.pluginToolbar],
          sourcePlugin: id,
          execute: (ref) async => _getEditorState(ref)?.redo(),
          canExecute: (ref) {
            final ctx = ref.watch(activeCommandContextProvider);
            return ctx is TiledEditorCommandContext && ctx.canRedo;
          },
        ),
        BaseCommand(
          id: 'tiled_map_properties',
          label: 'Map Properties',
          icon: const Icon(Icons.settings_overscan),
          defaultPositions: [AppCommandPositions.pluginToolbar],
          sourcePlugin: id,
          execute: (ref) async => _getEditorState(ref)?.inspectMapProperties(),
        ),
        BaseCommand(
          id: 'tiled_toggle_layers_panel',
          label: 'Toggle Layers',
          icon: Consumer(
            builder: (context, ref, _) {
              final ctx = ref.watch(activeCommandContextProvider);
              final isActive =
                  ctx is TiledEditorCommandContext && ctx.isLayersPanelVisible;
              return Icon(
                Icons.layers_outlined,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              );
            },
          ),
          defaultPositions: [AppCommandPositions.pluginToolbar],
          sourcePlugin: id,
          execute: (ref) async => _getEditorState(ref)?.toggleLayersPanel(),
        ),
        BaseCommand(
          id: 'tiled_toggle_grid',
          label: 'Toggle Grid',
          icon: Consumer(
            builder: (context, ref, _) {
              final ctx = ref.watch(activeCommandContextProvider);
              final isActive =
                  ctx is TiledEditorCommandContext && ctx.isGridVisible;
              return Icon(
                Icons.grid_on,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              );
            },
          ),
          defaultPositions: [tiledFloatingToolbar],
          sourcePlugin: id,
          execute: (ref) async => _getEditorState(ref)?.toggleGrid(),
        ),
        BaseCommand(
          id: 'tiled_subtool_paint',
          label: 'Paint Brush',
          icon: Consumer(
            builder: (context, ref, _) {
              final ctx = ref.watch(activeCommandContextProvider);
              final isActive = ctx is TiledEditorCommandContext &&
                  ctx.paintMode == TiledPaintMode.paint;
              return Icon(
                Icons.brush,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              );
            },
          ),
          defaultPositions: [paintToolsToolbar],
          sourcePlugin: id,
          execute: (ref) async =>
              _getEditorState(ref)?.setPaintMode(TiledPaintMode.paint),
          canExecute: (ref) {
            final ctx = ref.watch(activeCommandContextProvider);
            return ctx is TiledEditorCommandContext && ctx.mode == TiledEditorMode.paint;
          },
        ),
        BaseCommand(
          id: 'tiled_subtool_fill',
          label: 'Bucket Fill',
          icon: Consumer(
            builder: (context, ref, _) {
              final ctx = ref.watch(activeCommandContextProvider);
              final isActive = ctx is TiledEditorCommandContext &&
                  ctx.paintMode == TiledPaintMode.fill;
              return Icon(
                Icons.format_color_fill,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              );
            },
          ),
          defaultPositions: [paintToolsToolbar],
          sourcePlugin: id,
          execute: (ref) async =>
              _getEditorState(ref)?.setPaintMode(TiledPaintMode.fill),
          canExecute: (ref) {
            final ctx = ref.watch(activeCommandContextProvider);
            return ctx is TiledEditorCommandContext && ctx.mode == TiledEditorMode.paint;
          },
        ),
        BaseCommand(
          id: 'tiled_subtool_erase',
          label: 'Erase',
          icon: Consumer(
            builder: (context, ref, _) {
              final ctx = ref.watch(activeCommandContextProvider);
              final isActive = ctx is TiledEditorCommandContext &&
                  ctx.paintMode == TiledPaintMode.erase;
              return Icon(
                Icons.rectangle_outlined,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              );
            },
          ),
          defaultPositions: [paintToolsToolbar],
          sourcePlugin: id,
          execute: (ref) async =>
              _getEditorState(ref)?.setPaintMode(TiledPaintMode.erase),
          canExecute: (ref) {
            final ctx = ref.watch(activeCommandContextProvider);
            return ctx is TiledEditorCommandContext && ctx.mode == TiledEditorMode.paint;
          },
        ),
        BaseCommand(
          id: 'tiled_subtool_select',
          label: 'Select Tiles',
          icon: Consumer(
            builder: (context, ref, _) {
              final ctx = ref.watch(activeCommandContextProvider);
              final isActive = ctx is TiledEditorCommandContext &&
                  ctx.paintMode == TiledPaintMode.select;
              return Icon(
                Icons.select_all,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              );
            },
          ),
          defaultPositions: [paintToolsToolbar],
          sourcePlugin: id,
          execute: (ref) async =>
              _getEditorState(ref)?.setPaintMode(TiledPaintMode.select),
          canExecute: (ref) {
            final ctx = ref.watch(activeCommandContextProvider);
            return ctx is TiledEditorCommandContext && ctx.mode == TiledEditorMode.paint;
          },
        ),
        BaseCommand(
          id: 'tiled_subtool_move_selection',
          label: 'Move Selection',
          icon: Consumer(
            builder: (context, ref, _) {
              final ctx = ref.watch(activeCommandContextProvider);
              final isActive = ctx is TiledEditorCommandContext &&
                  ctx.paintMode == TiledPaintMode.move;
              return Icon(
                Icons.open_with,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              );
            },
          ),
          defaultPositions: [paintToolsToolbar],
          sourcePlugin: id,
          execute: (ref) async =>
              _getEditorState(ref)?.setPaintMode(TiledPaintMode.move),
          canExecute: (ref) {
            final ctx = ref.watch(activeCommandContextProvider);
            return ctx is TiledEditorCommandContext &&
                ctx.mode == TiledEditorMode.paint &&
                ctx.hasFloatingTileSelection;
          },
        ),
        BaseCommand(
          id: 'tiled_delete_selection',
          label: 'Delete Selection',
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          defaultPositions: [paintToolsToolbar],
          sourcePlugin: id,
          execute: (ref) async {
            _getEditorState(ref)?.notifier?.deleteFloatingSelection();
          },
          canExecute: (ref) {
            final ctx = ref.watch(activeCommandContextProvider);
            return ctx is TiledEditorCommandContext && ctx.hasFloatingTileSelection;
          },
        ),
        BaseCommand(
          id: 'tiled_reset_view',
          label: 'Reset View',
          icon: const Icon(Icons.filter_center_focus),
          defaultPositions: [tiledFloatingToolbar],
          sourcePlugin: id,
          execute: (ref) async => _getEditorState(ref)?.resetView(),
        ),
        BaseCommand(
          id: 'tiled_toggle_palette',
          label: 'Toggle Palette',
          icon: Consumer(
            builder: (context, ref, _) {
              final ctx = ref.watch(activeCommandContextProvider);
              final isActive =
                  ctx is TiledEditorCommandContext && ctx.isPaletteVisible;
              return Icon(
                Icons.palette_outlined,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              );
            },
          ),
          defaultPositions: [AppCommandPositions.pluginToolbar],
          sourcePlugin: id,
          execute: (ref) async => _getEditorState(ref)?.togglePalette(),
        ),
        BaseCommand(
          id: 'save_tmx',
          label: 'Save Map',
          icon: const Icon(Icons.save),
          defaultPositions: [AppCommandPositions.appBar],
          sourcePlugin: id,
          execute: (ref) async => ref.read(editorServiceProvider).saveCurrentTab(),
          canExecute: (ref) {
            final tabId = ref.watch(
              appNotifierProvider.select(
                (s) => s.value?.currentProject?.session.currentTab?.id,
              ),
            );
            if (tabId == null) return false;
            return ref
                    .watch(tabMetadataProvider.select((m) => m[tabId]))
                    ?.isDirty ??
                false;
          },
        ),
        BaseCommand(
          id: 'save_tmx_as',
          label: 'Save As...',
          icon: const Icon(Icons.save_as),
          defaultPositions: [AppCommandPositions.appBar],
          sourcePlugin: id,
          execute: (ref) async =>
              ref.read(editorServiceProvider).saveCurrentTabAs(),
        ),
        // Inside tiled_editor_plugin.dart -> 
BaseCommand(
  id: 'unified_export',
  label: 'Unified Export...',
  icon: const Icon(Icons.account_tree_sharp),
  defaultPositions: [AppCommandPositions.appBar],
  sourcePlugin: id,
  execute: (ref) async {
    final editor = _getEditorState(ref);
    if (editor?.mounted == true) {
      final rootUri = ref.read(tabMetadataProvider)[editor!.widget.tab.id]!.file.uri;
      
      Navigator.of(editor.context).push(
        MaterialPageRoute(
          builder: (_) => UnifiedExportScreen(
            rootFileUri: rootUri,
            tabId: editor.widget.tab.id,
          ),
        ),
      );
    }
  },
),
        BaseCommand(
          id: 'export_map',
          label: 'Export Map...',
          icon: const Icon(Icons.output_outlined),
          defaultPositions: [AppCommandPositions.appBar],
          sourcePlugin: id,
          execute: (ref) async {
            final editor = _getEditorState(ref);
            editor?.showExportDialog();
          },
        ),
      ];
  }

  @override
  String? get hotStateDtoType => null;
  @override
  Type? get hotStateDtoRuntimeType => null;
  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => null;
}
