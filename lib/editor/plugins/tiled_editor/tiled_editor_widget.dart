import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tiled/tiled.dart' hide Text;
import 'package:tiled/tiled.dart' as tiled show Text;
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Ensure this 
import 'package:xml/xml.dart';
import 'package:collection/collection.dart';
import '../../../app/app_notifier.dart';
import '../../../widgets/dialogs/folder_picker_dialog.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../models/editor_tab_models.dart';
import '../../services/editor_service.dart';
import '../../tab_metadata_notifier.dart';
import '../../../logs/logs_provider.dart';
import '../../../utils/toast.dart';

import 'tiled_command_context.dart';
import 'tiled_editor_models.dart';
import 'tiled_editor_plugin.dart';
import 'tiled_map_notifier.dart';
import 'tmx_writer.dart';
import '../../../command/command_widgets.dart';
import '../../models/editor_command_context.dart';
import 'widgets/layers_panel.dart';
import 'widgets/tile_palette.dart';
import 'tiled_paint_tools.dart';
import '../../../widgets/dialogs/file_explorer_dialogs.dart';
import 'widgets/map_properties_dialog.dart';
import 'widgets/new_layer_dialog.dart';
import 'widgets/new_tileset_dialog.dart';
import 'project_tsx_provider.dart';

import 'tiled_map_painter.dart';
import 'inspector/inspector_dialog.dart'; // ADDED
import 'widgets/object_editor_app_bar.dart';
import 'widgets/paint_editor_app_bar.dart';
import 'package:machine/settings/settings_notifier.dart';
import 'tiled_editor_settings_model.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'widgets/export_dialog.dart';

import 'widgets/sprite_picker_dialog.dart'; // Import
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart'; // Import for models

class TiledEditorWidget extends EditorWidget {
  @override
  final TiledEditorTab tab;

  const TiledEditorWidget({required super.key, required this.tab})
    : super(tab: tab);

  @override
  TiledEditorWidgetState createState() => TiledEditorWidgetState();
}

class TiledEditorWidgetState extends EditorWidgetState<TiledEditorWidget> {
  TiledMapNotifier? get notifier => _notifier;
  TiledMapNotifier? _notifier;


  int _selectedLayerId = -1;
  Tileset? _selectedTileset;
  Rect? _selectedTileRect;

  String? _baseContentHash;
  
  final Map<String, String> _tmxToProjectPaths = {};
  Set<String> _requiredAssetUris = const {};
  bool _isLoading = true;
  Object? _loadingError;

  // General state
  bool _showGrid = true;
  bool _isPaletteVisible = false;
  bool _isLayersPanelVisible = false;
  TiledEditorMode _mode = TiledEditorMode.panZoom;
  
  bool get isZoomMode => (_mode == TiledEditorMode.panZoom);
  // Paint mode state
  TiledPaintMode _paintMode = TiledPaintMode.paint;
  Rect? _tileMarqueeSelection;
  Offset? _dragStartOffsetInSelection;
  
  // Object mode state
  ObjectTool _activeObjectTool = ObjectTool.select;
  bool _isSnapToGridEnabled = true;
  Offset? _dragStartMapPosition;
  Map<int, Point>? _initialObjectPositions;

  // Temporary drawing state
  List<Point> _inProgressPoints = [];
  Rect? _previewShape;
  Rect? _marqueeSelection; // NEW: Specific state for marquee selection

  static const double _kMinPaletteHeight = 150.0;
  static const double _kDefaultPaletteHeight = 200.0;
  double _paletteHeight = _kDefaultPaletteHeight;

  late final TransformationController _transformationController;
  String? _lastTilesetParentUri;
  // --- Public Methods for Commands ---
  void editMapProperties() => _editMapProperties();
  void addTileset() => _addTileset();
  void addLayer() => _addLayer();
  void toggleGrid() {
    setState(() => _showGrid = !_showGrid);
    syncCommandContext();
  }

  void _handlePaletteResize(DragUpdateDetails details) {
    setState(() {
      final newHeight = _paletteHeight - details.delta.dy;
      _paletteHeight = newHeight.clamp(
        _kMinPaletteHeight,
        MediaQuery.of(context).size.height * 0.8,
      );
    });
  }
  
  TiledEditorMode getMode() => _mode;
  
  void setMode(TiledEditorMode newMode) {
    if (_mode == newMode) {
      // If tapping the active mode, toggle back to Pan/Zoom
      setState(() => _mode = TiledEditorMode.panZoom);
    } else {
      setState(() => _mode = newMode);
    }
    syncCommandContext();
  }

  void exitObjectMode() {
    setMode(TiledEditorMode.panZoom);
  }

  void exitPaintMode() {
    setMode(TiledEditorMode.panZoom);
  }

  void resetView() => _transformationController.value = Matrix4.identity();
  void togglePalette() {
    setState(() => _isPaletteVisible = !_isPaletteVisible);
    syncCommandContext();
  }

  void toggleLayersPanel() {
    setState(() => _isLayersPanelVisible = !_isLayersPanelVisible);
    syncCommandContext();
  }
  
  void setActiveObjectTool(ObjectTool tool) {
    setState(() => _activeObjectTool = tool);
    syncCommandContext();
  }

  void setPaintMode(TiledPaintMode mode) {
    setState(() => _paintMode = mode);
    syncCommandContext();
  }

  @override
  void syncCommandContext() {
    final isPolyToolActive = _activeObjectTool == ObjectTool.addPolygon ||
        _activeObjectTool == ObjectTool.addPolyline;

    Widget? appBarOverride;
    switch (_mode) {
      case TiledEditorMode.paint:
        appBarOverride = PaintEditorAppBar(onExit: exitPaintMode);
        break;
      case TiledEditorMode.object:
        appBarOverride = ObjectEditorAppBar(
          onExit: exitObjectMode,
          isSnapToGridEnabled: _isSnapToGridEnabled,
          onToggleSnapToGrid: () {
            setState(() => _isSnapToGridEnabled = !_isSnapToGridEnabled);
            syncCommandContext();
          },
          isObjectSelected: _notifier?.selectedObjects.isNotEmpty ?? false,
          onInspectObject: _inspectSelectedObject,
          onDeleteObject: _deleteSelectedObject,
          showFinishShapeButton: isPolyToolActive && _inProgressPoints.isNotEmpty,
          onFinishShape: _finalizePolygon,
        );
        break;
      case TiledEditorMode.panZoom:
        appBarOverride = null;
        break;
    }

    ref.read(commandContextProvider(widget.tab.id).notifier).state =
        TiledEditorCommandContext(
      mode: _mode,
      isGridVisible: _showGrid,
      canUndo: _notifier?.canUndo ?? false,
      canRedo: _notifier?.canRedo ?? false,
      isSnapToGridEnabled: _isSnapToGridEnabled,
      isPaletteVisible: _isPaletteVisible,
      isLayersPanelVisible: _isLayersPanelVisible,
      paintMode: _paintMode,
      activeObjectTool: _activeObjectTool,
      hasPolygonPoints: _inProgressPoints.isNotEmpty,
      isObjectSelected: _notifier?.selectedObjects.isNotEmpty ?? false,
      hasFloatingTileSelection: _notifier?.hasFloatingSelection ?? false,
      appBarOverride: appBarOverride,
    );
  }

  @override
  void init() {
    _baseContentHash = widget.tab.initialBaseContentHash;
    _transformationController = TransformationController();
    _transformationController.addListener(() => setState(() {}));
  }

  @override
  void onFirstFrameReady() {
    if (mounted && !widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
    if (_baseContentHash == "new_map") {
      ref.read(editorServiceProvider).markCurrentTabDirty();
    }
    _initializeAndLoadMap();
    syncCommandContext();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _notifier?.removeListener(_onMapChanged);
    _notifier?.dispose();
    super.dispose();
  }

  Future<void> _initializeAndLoadMap() async {
    try {
      final repo = ref.read(projectRepositoryProvider)!;
      final tmxFileUri = ref.read(tabMetadataProvider)[widget.tab.id]!.file.uri;
      final tmxParentUri = repo.fileHandler.getParentUri(tmxFileUri);
      
      final tsxProvider = ProjectTsxProvider(repo, tmxParentUri);
      final tsxProviders = await ProjectTsxProvider.parseFromTmx(
        widget.tab.initialTmxContent,
        tsxProvider.getProvider,
      );
      
      final map = TileMapParser.parseTmx(
        widget.tab.initialTmxContent,
        tsxList: tsxProviders,
      );
      _fixupParsedMap(map, widget.tab.initialTmxContent);

      // Collect URIs and populate the path mapping
      final uris = await _collectAssetUris(map);
      
      // Load the assets
      final assetDataMap = await ref.read(assetMapProvider(widget.tab.id).notifier).updateUris(uris);

      // Apply fixups using the loaded assets and the mapping
      _fixupTilesetsAfterImageLoad(map, assetDataMap);

      if (!mounted) return;
      setState(() {
        _notifier = TiledMapNotifier(map);
        _notifier!.addListener(_onMapChanged);

        _selectedLayerId = map.layers.whereType<TileLayer>().firstOrNull?.id ?? -1;
        _selectedTileset = map.tilesets.firstOrNull;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onMapChanged();
      });
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Failed to load TMX map');
      if (mounted) {
        setState(() {
          _loadingError = e;
          _isLoading = false;
        });
      }
    }
  }
  
Future<Set<String>> _collectAssetUris(TiledMap map) async {
    final uris = <String>{};
    final newMappings = <String, String>{};
    
    final repo = ref.read(projectRepositoryProvider)!;
    final project = ref.read(currentProjectProvider)!;
    final talker = ref.read(talkerProvider);
    
    final tmxFile = ref.read(tabMetadataProvider)[widget.tab.id]!.file;
    final tmxParentUri = repo.fileHandler.getParentUri(tmxFile.uri);

    Future<void> resolveAndAdd(String? rawPath, String parentUri) async {
      if (rawPath == null || rawPath.isEmpty) return;
      try {
        final resolvedFile = await repo.fileHandler.resolvePath(parentUri, rawPath);
        if (resolvedFile != null) {
          final displayPath = repo.fileHandler.getPathForDisplay(
            resolvedFile.uri,
            relativeTo: project.rootUri,
          );
          uris.add(displayPath);
          newMappings[rawPath] = displayPath;
        } else {
          talker.warning('TiledEditor: Could not resolve path "$rawPath" relative to "$parentUri"');
        }
      } catch (e) {
        talker.warning('TiledEditor: Failed to resolve path: $rawPath ($e)');
      }
    }

    // 1. Process Tilesets & Image Layers (Existing logic)
    for (final tileset in map.tilesets) {
      var currentBaseUri = tmxParentUri;
      if (tileset.source != null) {
        final tsxFile = await repo.fileHandler.resolvePath(tmxParentUri, tileset.source!);
        if (tsxFile != null) {
          currentBaseUri = repo.fileHandler.getParentUri(tsxFile.uri);
        }
      }
      await resolveAndAdd(tileset.image?.source, currentBaseUri);
    }
    for (final layer in map.layers) {
      if (layer is ImageLayer) {
        await resolveAndAdd(layer.image.source, tmxParentUri);
      }
    }

    // --- FIX: Access properties using .byName ---
    // Property: tp_atlases (String, comma-separated relative paths)
    // Check if property exists first
    if (map.properties.byName.containsKey('tp_atlases')) {
      final prop = map.properties.byName['tp_atlases'];
      if (prop is StringProperty && prop.value.isNotEmpty) {
        talker.info('TiledEditor: Found linked atlases: ${prop.value}');
        final paths = prop.value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
        for (final path in paths) {
          await resolveAndAdd(path, tmxParentUri);
        }
      }
    }
    
    _tmxToProjectPaths.addAll(newMappings);
    return uris;
  }
  
  Future<void> _rebuildAssetUriSet() async {
    if (_notifier == null) return;
    final uris = await _collectAssetUris(_notifier!.map);
    ref.read(assetMapProvider(widget.tab.id).notifier).updateUris(uris);
  }
  
  Future<void> reloadImageSource({
    required Object parentObject,
    required String oldSourcePath,
    required String newProjectPath,
  }) async {
    if (_notifier == null) return;
        
    try {
      final repo = ref.read(projectRepositoryProvider)!;
      final project = ref.read(currentProjectProvider)!;
      final tmxFileUri = ref.read(tabMetadataProvider)[widget.tab.id]!.file.uri;

      // 1. Load asset to get dimensions
      final assetData = await ref.read(assetDataProvider(newProjectPath).future);
      if (assetData is! ImageAssetData) {
        throw (assetData as ErrorAssetData).error;
      }
      final newImage = assetData.image;

      // 2. Calculate RELATIVE path for TMX storage
      // We rely on "Display Paths" to calculate relative strings, assuming SAF structure mirrors display
      final tmxDisplayPath = repo.fileHandler.getPathForDisplay(tmxFileUri, relativeTo: project.rootUri);
      final tmxDirDisplayPath = p.dirname(tmxDisplayPath);
      
      final newRelativePathForTmx = p.relative(newProjectPath, from: tmxDirDisplayPath).replaceAll(r'\', '/');

      // 3. Update Notifier (Model)
      _notifier!.updateImageSource(
        parentObject: parentObject,
        newSourcePath: newRelativePathForTmx,
        newWidth: newImage.width,
        newHeight: newImage.height,
      );
      
      // 4. Rebuild mappings (will map newRelativePathForTmx -> newProjectPath)
      await _rebuildAssetUriSet();
      
      MachineToast.info('Image source updated successfully.');
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Failed to reload image source');
      MachineToast.error('Failed to reload image: $e');
    }
  }
  
  // --- NEW: Helper method to fix parsing issues from the `tiled` package ---
  void _fixupParsedMap(TiledMap map, String tmxContent) {
    final xmlDocument = XmlDocument.parse(tmxContent);
    final layerElements = xmlDocument.rootElement.findAllElements('layer');
    final objectGroupElements = xmlDocument.rootElement.findAllElements('objectgroup');

    // FIX 1: Handle un-encoded tile layer data.
    for (final layerElement in layerElements) {
      final layerId = int.tryParse(layerElement.getAttribute('id') ?? '');
      if (layerId == null) continue;
      
      final layer = map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
      if (layer != null && (layer.tileData == null || layer.tileData!.isEmpty)) {
        final dataElement = layerElement.findElements('data').firstOrNull;
        if (dataElement != null && dataElement.getAttribute('encoding') == null) {
          final tileElements = dataElement.findElements('tile');
          final gids = tileElements.map((t) => int.tryParse(t.getAttribute('gid') ?? '0') ?? 0).toList();
          if(gids.isNotEmpty) {
            layer.tileData = Gid.generate(gids, layer.width, layer.height);
          }
        }
      }
    }

    // FIX 2: Handle object types (point, ellipse, etc.).
    for (final objectGroupElement in objectGroupElements) {
      final layerId = int.tryParse(objectGroupElement.getAttribute('id') ?? '');
      if (layerId == null) continue;

      final objectGroup = map.layers.firstWhereOrNull((l) => l.id == layerId) as ObjectGroup?;
      if (objectGroup == null) continue;

      final objectElements = objectGroupElement.findAllElements('object');
      for (final objectElement in objectElements) {
        final objectId = int.tryParse(objectElement.getAttribute('id') ?? '');
        if (objectId == null) continue;

        final tiledObject = objectGroup.objects.firstWhereOrNull((o) => o.id == objectId);
        if (tiledObject != null) {
          final hasEllipse = objectElement.findElements('ellipse').isNotEmpty;
          final hasPoint = objectElement.findElements('point').isNotEmpty;
          
          if (hasEllipse) {
            tiledObject.ellipse = true;
            tiledObject.rectangle = false;
            tiledObject.point = false;
          } else if (hasPoint) {
            tiledObject.point = true;
            tiledObject.rectangle = false;
            tiledObject.ellipse = false;
          }
        }
      }
    }

    // --- NEW: FIX 3: Ensure all layers have a unique ID. ---
    var nextAvailableId = map.nextLayerId;

    // Helper to find the max ID recursively.
    int findMaxId(List<Layer> layers) {
      var maxId = 0;
      for (final layer in layers) {
        if (layer.id != null) {
          maxId = max(maxId, layer.id!);
        }
        if (layer is Group) {
          maxId = max(maxId, findMaxId(layer.layers));
        }
      }
      return maxId;
    }

    // If the map doesn't specify the next ID, we calculate it.
    if (nextAvailableId == null) {
      final maxLayerId = findMaxId(map.layers);
      nextAvailableId = maxLayerId + 1;
    }

    // Helper to assign IDs recursively.
    void assignIds(List<Layer> layers) {
      for (final layer in layers) {
        if (layer.id == null) {
          layer.id = nextAvailableId;
          nextAvailableId = nextAvailableId! + 1;
        }
        if (layer is Group) {
          assignIds(layer.layers);
        }
      }
    }

    assignIds(map.layers);
    
    // Update the map object so new layers created in the UI get a valid ID.
    map.nextLayerId = nextAvailableId;
  }
  
  void _fixupTilesetsAfterImageLoad(TiledMap map, Map<String, AssetData> assetDataMap) {
    for (final tileset in map.tilesets) {
      if (tileset.tiles.isEmpty && tileset.image?.source != null) {
        // Use the mapping to find the correct key for assetDataMap
        final rawSource = tileset.image!.source!;
        final projectPath = _tmxToProjectPaths[rawSource];
        
        if (projectPath != null) {
          final asset = assetDataMap[projectPath];
          if (asset is ImageAssetData) {
            final loadedImage = asset.image;
            final currentTiledImage = tileset.image!;

            if (currentTiledImage.width == null || currentTiledImage.height == null) {
              tileset.image = TiledImage(
                source: currentTiledImage.source,
                width: loadedImage.width,
                height: loadedImage.height,
              );
            }

            final tileWidth = tileset.tileWidth;
            final tileHeight = tileset.tileHeight;
            final imageWidth = tileset.image!.width!;
            final imageHeight = tileset.image!.height!;

            if (tileWidth != null && tileHeight != null && tileWidth > 0 && tileHeight > 0) {
              final columns = (imageWidth - tileset.margin * 2 + tileset.spacing) ~/ (tileWidth + tileset.spacing);
              final rows = (imageHeight - tileset.margin * 2 + tileset.spacing) ~/ (tileHeight + tileset.spacing);
              final tileCount = columns * rows;
              
              tileset.columns = columns;
              tileset.tileCount = tileCount;
              tileset.tiles = [for (var i = 0; i < tileCount; ++i) Tile(localId: i)];
            }
          }
        }
      }
    }
  }

  void _onMapChanged() {
    ref.read(editorServiceProvider).markCurrentTabDirty();
    
    // Re-resolve paths (e.g. if a tileset was added) and then force a UI update
    _rebuildAssetUriSet().then((_) {
      if (mounted) setState(() {});
    });
    
    syncCommandContext();
    setState(() {}); // Immediate update for non-asset changes
  }

  void _editMapProperties() async {
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => MapPropertiesDialog(map: _notifier!.map),
    );
    if (result != null) {
      _notifier!.updateMapProperties(
        width: result['width']!,
        height: result['height']!,
        tileWidth: result['tileWidth']!,
        tileHeight: result['tileHeight']!,
      );
    }
  }
  
  Map<String, AssetData>? _getAssetDataMap() {
    final assetMapAsync = ref.read(assetMapProvider(widget.tab.id));
    final assetMap = assetMapAsync.valueOrNull;
    if (assetMap == null) {
      MachineToast.info("Assets are still loading, please wait.");
      return null;
    }
    return assetMap;
  }
  
  void showExportDialog() {
    final assetMap = _getAssetDataMap();
    if (_notifier == null || assetMap == null) return;

    showDialog(
      context: context,
      builder: (_) => ExportDialog(
        notifier: _notifier!,
        talker: ref.read(talkerProvider),
        assetDataMap: assetMap,
      ),
    );
  }  
  
  void inspectMapProperties() {
    final assetMap = _getAssetDataMap();
    if (_notifier == null || assetMap == null) return;

    showDialog(
      context: context,
      builder: (_) => InspectorDialog(
        target: _notifier!.map,
        title: 'Map Properties',
        notifier: _notifier!,
        editorKey: widget.tab.editorKey,
        assetDataMap: assetMap,
      ),
    );
  }

  Future<void> _addTileset() async {
    final relativeImagePath = await showDialog<String>(
      context: context,
      builder: (_) => FileOrFolderPickerDialog(initialUri: _lastTilesetParentUri),
    );
    if (relativeImagePath == null || !mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => NewTilesetDialog(imagePath: relativeImagePath),
    );
    if (result == null || !mounted) return;

    try {
      final repo = ref.read(projectRepositoryProvider)!;
      final project = ref.read(currentProjectProvider)!;
      final tmxFileUri = ref.read(tabMetadataProvider)[widget.tab.id]!.file.uri;

      // Update last path for convenience
      final imageFile = await repo.fileHandler.resolvePath(project.rootUri, relativeImagePath);
      if (imageFile != null) {
        _lastTilesetParentUri = repo.fileHandler.getParentUri(imageFile.uri);
      }

      // Calculate path relative to TMX
      final tmxDisplayPath = repo.fileHandler.getPathForDisplay(tmxFileUri, relativeTo: project.rootUri);
      final tmxDirDisplayPath = p.dirname(tmxDisplayPath);
      
      final imagePathRelativeToTmx = p.relative(
        relativeImagePath,
        from: tmxDirDisplayPath,
      ).replaceAll(r'\', '/');

      // Load data
      final assetData = await ref.read(assetDataProvider(relativeImagePath).future);
      if (assetData is! ImageAssetData) throw Exception("Failed to load image asset");
      final image = assetData.image;

      final tileWidth = result['tileWidth'] as int;
      final tileHeight = result['tileHeight'] as int;
      final columns = (image.width) ~/ tileWidth;
      final tileCount = columns * (image.height ~/ tileHeight);

      int nextGid = 1;
      if (_notifier!.map.tilesets.isNotEmpty) {
        final last = _notifier!.map.tilesets.last;
        nextGid = (last.firstGid ?? 0) + (last.tileCount ?? 0);
      }

      final newTileset = Tileset(
        name: result['name'],
        firstGid: nextGid,
        tileWidth: tileWidth,
        tileHeight: tileHeight,
        tileCount: tileCount,
        columns: columns,
        image: TiledImage(
          source: imagePathRelativeToTmx,
          width: image.width,
          height: image.height,
        ),
      );

      // Add to map -> triggers onMapChanged -> triggers rebuildAssetUriSet -> resolves path
      await _notifier!.addTileset(newTileset);

    } catch (e, st) {
      MachineToast.error('Failed to add tileset: $e');
      ref.read(talkerProvider).handle(e, st, 'Failed to add tileset');
    }
  }
  
  void _deleteSelectedTileset() async {
    if (_notifier == null || _selectedTileset == null) return;

    final tilesetToDelete = _selectedTileset!;
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Tileset "${tilesetToDelete.name}"?',
      content:
          'Are you sure you want to delete this tileset? Tiles using it may disappear. This action can be undone.',
    );

    if (confirm) {
      _notifier!.deleteTileset(tilesetToDelete);
      setState(() {
        _selectedTileset = null;
        _selectedTileRect = null;
      });
    }
  }
  
    void _clearUnusedTilesets() async {
    if (_notifier == null) return;
    
    final unused = _notifier!.findUnusedTilesets();

    if (unused.isEmpty) {
      MachineToast.info("No unused tilesets found.");
      return;
    }

    final confirm = await showConfirmDialog(
      context,
      title: 'Clear Unused Tilesets?',
      content:
          'This will remove ${unused.length} tileset(s) that are not currently used by any layers. This action can be undone.',
    );

    if (confirm) {
      // Check if the currently selected tileset is among those to be removed
      final selectedIsUnused = unused.any((ts) => ts.name == _selectedTileset?.name);
      
      _notifier!.removeTilesets(unused);
      
      if (selectedIsUnused) {
        setState(() {
          _selectedTileset = null;
          _selectedTileRect = null;
        });
      }

      MachineToast.info("Removed ${unused.length} tileset(s).");
    }
  }
  
  void _inspectSelectedTileset() {
    final assetMap = _getAssetDataMap();
    if (_notifier == null || _selectedTileset == null ||assetMap==null) return;
    showDialog(
      context: context,
      builder: (_) => InspectorDialog(
        target: _selectedTileset!,
        assetDataMap: assetMap!,
        title: '${_selectedTileset!.name ?? 'Tileset'} Properties',
        notifier: _notifier!,
        editorKey: widget.tab.editorKey,
      ),
    );
  }

  void _addLayer() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const NewLayerDialog(),
    );
    if (result != null) {
      _notifier!.addLayer(name: result['name'], type: result['type']);
    }
  }
  

  void _deleteLayer(int layerId) async {
    if (_notifier == null) return;
    final layerToDelete =
        _notifier!.map.layers.firstWhereOrNull((l) => l.id == layerId);
    if (layerToDelete == null) return;

    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Layer "${layerToDelete.name}"?',
      content: 'Are you sure you want to delete this layer? This can be undone.',
    );

    if (confirm) {
      final oldIndex = _notifier!.map.layers.indexWhere((l) => l.id == layerId);
      _notifier!.deleteLayer(layerId);
      if (_selectedLayerId == layerId) {
        final newIndex = (oldIndex - 1).clamp(0, _notifier!.map.layers.length - 1);
        final newSelectedLayer =
            _notifier!.map.layers.isEmpty ? null : _notifier!.map.layers[newIndex];
        _onLayerSelect(newSelectedLayer?.id ?? -1);
      }
    }
  }
  
  void _onLayerSelect(int id) {
    final layer = notifier?.map.layers.firstWhereOrNull((l) => l.id == id);
    if (layer == null) return;

    var newMode = _mode;
    // If the current mode is incompatible with the newly selected layer type,
    // revert to the default Pan/Zoom mode.
    if (_mode == TiledEditorMode.paint && layer is! TileLayer) {
      newMode = TiledEditorMode.panZoom;
      MachineToast.info("Switched to Pan/Zoom mode. Selected layer is not a Tile Layer.");
    } else if (_mode == TiledEditorMode.object && layer is! ObjectGroup) {
      newMode = TiledEditorMode.panZoom;
      MachineToast.info("Switched to Pan/Zoom mode. Selected layer is not an Object Layer.");
    }

    setState(() {
      _selectedLayerId = id;
      _mode = newMode;
    });
    syncCommandContext();
  }

  
  void _showLayerInspector(Layer layer) {
    final assetMap = _getAssetDataMap();
    if (_notifier == null || assetMap == null) return;
    
    showDialog(
      context: context,
      builder: (_) => InspectorDialog(
        target: layer,
        title: '${layer.name} Properties',
        notifier: _notifier!,
        editorKey: widget.tab.editorKey,
        assetDataMap: assetMap,
      ),
    );
  }
  
  void _inspectObject(TiledObject object) {
    final assetMap = _getAssetDataMap();
    if (assetMap == null || _notifier == null) return;
    
    showDialog(
      context: context,
      builder: (_) => InspectorDialog(
        target: object,
        assetDataMap: assetMap,
        title: '${object.name.isNotEmpty ? object.name : 'Object'} Properties',
        notifier: _notifier!,
        editorKey: widget.tab.editorKey,
      ),
    );
  }
  
  void _inspectSelectedObject() {
    final assetMap = _getAssetDataMap();
    if(assetMap==null) return;
    if (_notifier == null) return;
    final selection = _notifier!.selectedObjects;
    if (selection.length != 1) return;

    final target = selection.first;
    showDialog(
      context: context,
      builder: (_) => InspectorDialog(
        target: target,
        assetDataMap: assetMap!,
        title: '${target.name.isNotEmpty ? target.name : 'Object'} Properties',
        notifier: _notifier!,
        editorKey: widget.tab.editorKey,
      ),
    );
  }
  
    void _deleteSelectedObject() async {
    if (_notifier == null || _notifier!.selectedObjects.isEmpty) return;

    final count = _notifier!.selectedObjects.length;
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Object${count > 1 ? 's' : ''}?',
      content:
          'Are you sure you want to delete the selected ${count > 1 ? '$count objects' : 'object'}? This action can be undone.',
    );

    if (confirm) {
      _notifier!.deleteSelectedObjects(_selectedLayerId);
    }
  }
  
  void _onInteractionUpdate(Offset localPosition, {bool isStart = false}) {
    switch (_mode) {
      case TiledEditorMode.paint:
        if (isStart) notifier?.beginTileStroke(_selectedLayerId);
        _handlePaintInteraction(localPosition, isStart: isStart);
        break;
      case TiledEditorMode.object:
        _handleObjectInteraction(localPosition, isStart: isStart);
        break;
      case TiledEditorMode.panZoom:
        // Do nothing, handled by InteractiveViewer
        break;
    }
  }
  

  void _onInteractionCancel() {
    switch (_mode) {
      case TiledEditorMode.paint:
        // For paint mode, we can treat cancel like an end, as the history
        // entry is only created on endStroke anyway. If a stroke was in
        // progress, this cleans it up without committing.
        notifier?.endTileStroke(_selectedLayerId);
        break;

      case TiledEditorMode.object:
        // This is a pure cleanup method for object mode. It reverts any
        // temporary state without committing changes to the model or history.
        if (_initialObjectPositions != null && notifier != null) {
          // If a move was in progress, snap objects back to original positions.
          notifier!.beginObjectChange(_selectedLayerId); // Start a "change"
          for (final obj in notifier!.selectedObjects) {
            final initialPos = _initialObjectPositions![obj.id];
            if (initialPos != null) {
              obj.x = initialPos.x;
              obj.y = initialPos.y;
            }
          }
          notifier!.endObjectChange(_selectedLayerId); // End it to revert visuals
          _initialObjectPositions = null;
        }

        if (_activeObjectTool == ObjectTool.addPolygon ||
            _activeObjectTool == ObjectTool.addPolyline) {
          // If a poly tool was cancelled mid-drag, remove the temporary point
          if (_inProgressPoints.isNotEmpty) {
            _inProgressPoints.removeLast();
            if (_inProgressPoints.isEmpty) {
              // If that was the first point, cancel the history entry.
              notifier?.endObjectChange(_selectedLayerId);
            }
          }
        }
        break;

      case TiledEditorMode.panZoom:
        // Nothing to do for pan/zoom.
        break;
    }

    setState(() {
      _dragStartMapPosition = null;
      _previewShape = null;
      _marqueeSelection = null;
      _initialObjectPositions = null;
    });
    syncCommandContext();
  }

  void _onInteractionEnd() {
    switch (_mode) {
      case TiledEditorMode.paint:
        _handlePaintInteractionEnd();
        break;
      case TiledEditorMode.object:
        _handleObjectInteractionEnd();
        break;
      case TiledEditorMode.panZoom:
        // Do nothing
        break;
    }
    syncCommandContext();
  }

  void _handlePaintInteraction(Offset localPosition, {bool isStart = false}) {
    if (isZoomMode || _selectedLayerId == -1) return;
    final layer = notifier?.map.layers.firstWhereOrNull((l) => l.id == _selectedLayerId);
    if (layer is! TileLayer) {
      if(isStart) {
        MachineToast.info("Select a Tile Layer.");
      }
      return;
    }

    final inverseMatrix = _transformationController.value.clone()..invert();
    final mapPosition = MatrixUtils.transformPoint(
      inverseMatrix,
      localPosition,
    );

    final tileWidth = notifier!.map.tileWidth;
    final tileHeight = notifier!.map.tileHeight;
    final mapX = (mapPosition.dx / tileWidth).floor();
    final mapY = (mapPosition.dy / tileHeight).floor();

    switch (_paintMode) {
      case TiledPaintMode.paint:
        if (_selectedTileset != null && _selectedTileRect != null) {
          notifier!.setStamp(
            mapX,
            mapY,
            _selectedLayerId,
            _selectedTileset!,
            _selectedTileRect!,
          );
        }
        break;
      case TiledPaintMode.erase:
        // Erase a 1x1 tile for now. Could be extended to use a brush size.
        notifier!.eraseTiles(
          mapX,
          mapY,
          _selectedLayerId,
          const Rect.fromLTWH(0, 0, 1, 1),
        );
        break;
      case TiledPaintMode.fill:
        if (_selectedTileset != null && _selectedTileRect != null) {
          notifier!.bucketFill(
            mapX,
            mapY,
            _selectedLayerId,
            _selectedTileset!,
            _selectedTileRect!,
          );
        } else {
          MachineToast.info(
            "Select a tile or stamp from the palette to use for filling.",
          );
        }
        break;
      case TiledPaintMode.select:
        _handleTileSelect(localPosition, isStart: isStart);
        break;
      case TiledPaintMode.move:
        _handleTileMove(localPosition, isStart: isStart);
        break;
    }
  }
  
  void _paintStamp(Offset localPosition) {
    if (isZoomMode ||
        _selectedTileset == null ||
        _selectedTileRect == null ||
        _selectedLayerId == -1)
      return;

    final inverseMatrix = _transformationController.value.clone()..invert();
    final mapPosition = MatrixUtils.transformPoint(
      inverseMatrix,
      localPosition,
    );

    final tileWidth = notifier!.map.tileWidth;
    final tileHeight = notifier!.map.tileHeight;
    final startX = (mapPosition.dx / tileWidth).floor();
    final startY = (mapPosition.dy / tileHeight).floor();

    notifier!.setStamp(
      startX,
      startY,
      _selectedLayerId,
      _selectedTileset!,
      _selectedTileRect!,
    );
  }
  
  void _handleTileSelect(Offset localPosition, {required bool isStart}) {
    final mapPosition = _getMapPosition(localPosition);
    if (isStart) {
      _dragStartMapPosition = mapPosition;
      notifier?.setTileSelection(null, _selectedLayerId); // Clear previous selection
    } else {
      if (_dragStartMapPosition == null) return;
      setState(() {
        _tileMarqueeSelection = Rect.fromPoints(_dragStartMapPosition!, mapPosition);
      });
    }
  }
  
  void _handleTileMove(Offset localPosition, {required bool isStart}) {
    if (notifier?.hasFloatingSelection != true) return;
    final mapPosition = _getMapPosition(localPosition);

    if (isStart) {
      // Drag started. Calculate the offset from the selection's top-left corner.
      final selectionPos = notifier!.floatingSelectionPosition!;
      final selectionPixelX = selectionPos.x * notifier!.map.tileWidth;
      final selectionPixelY = selectionPos.y * notifier!.map.tileHeight;
      _dragStartOffsetInSelection = Offset(
        mapPosition.dx - selectionPixelX,
        mapPosition.dy - selectionPixelY,
      );
    } else {
      // Drag is in progress.
      if (_dragStartOffsetInSelection == null) return; // Should not happen if isStart was called

      // Calculate the new top-left corner of the selection by subtracting the initial offset.
      final newTopLeftPixelX = mapPosition.dx - _dragStartOffsetInSelection!.dx;
      final newTopLeftPixelY = mapPosition.dy - _dragStartOffsetInSelection!.dy;

      // Convert the new pixel position to tile coordinates.
      final tileX = (newTopLeftPixelX / notifier!.map.tileWidth).floor();
      final tileY = (newTopLeftPixelY / notifier!.map.tileHeight).floor();

      notifier!.updateFloatingSelectionPosition(Point(x: tileX.toDouble(), y: tileY.toDouble()));
    }
  }
  
// Inside TiledEditorWidgetState

  void _handlePaintInteractionEnd() {
    if (_paintMode == TiledPaintMode.select && _tileMarqueeSelection != null) {
      final rect = _tileMarqueeSelection!;
      final tileWidth = notifier!.map.tileWidth;
      final tileHeight = notifier!.map.tileHeight;

      // Ensure correct integer conversion and ordering
      final startTileX = (rect.left / tileWidth).floor();
      final startTileY = (rect.top / tileHeight).floor();
      final endTileX = (rect.right / tileWidth).floor();
      final endTileY = (rect.bottom / tileHeight).floor();

      final selection = Rect.fromLTWH(
        min(startTileX, endTileX).toDouble(),
        min(startTileY, endTileY).toDouble(),
        (startTileX - endTileX).abs() + 1,
        (startTileY - endTileY).abs() + 1,
      );
      
      notifier?.setTileSelection(selection, _selectedLayerId);
      notifier?.cutSelection(_selectedLayerId);      
    } else if (notifier?.hasFloatingSelection == true && _paintMode != TiledPaintMode.move) {
      notifier?.stampFloatingSelection(_selectedLayerId);
    }
    notifier?.endTileStroke(_selectedLayerId);
    setState(() {
      _dragStartMapPosition = null;
      _tileMarqueeSelection = null;
      _dragStartOffsetInSelection = null; // Add this line to clear the offset
    });
    
    // syncCommandContext() is called in the parent _onInteractionEnd, which is correct.
  }

  Offset _getMapPosition(Offset localPosition) {
    final inverseMatrix = _transformationController.value.clone()..invert();
    return MatrixUtils.transformPoint(inverseMatrix, localPosition);
  }

  Offset _snapOffsetToGrid(Offset offset) {
    if (!_isSnapToGridEnabled || notifier == null) return offset;
    final tileWidth = notifier!.map.tileWidth.toDouble();
    final tileHeight = notifier!.map.tileHeight.toDouble();
    return Offset(
      (offset.dx / tileWidth).round() * tileWidth,
      (offset.dy / tileHeight).round() * tileHeight,
    );
  }
  
  TexturePackerSpriteData? _findSpriteDataInAssets(String spriteName) {
    final assetMap = _getAssetDataMap();
    if (assetMap == null) return null;

    for (final asset in assetMap.values) {
      if (asset is TexturePackerAssetData) {
        if (asset.frames.containsKey(spriteName)) {
          return asset.frames[spriteName];
        }
        // Check animations too (use first frame)
        if (asset.animations.containsKey(spriteName)) {
          final firstFrame = asset.animations[spriteName]!.firstOrNull;
          if (firstFrame != null && asset.frames.containsKey(firstFrame)) {
            return asset.frames[firstFrame];
          }
        }
      }
    }
    return null;
  }
  
  Future<void> _createSpriteObjectFromTap() async {
    final layer = notifier?.map.layers.firstWhereOrNull((l) => l.id == _selectedLayerId);
    if (layer is! ObjectGroup || _dragStartMapPosition == null) return;

    // 1. Collect all available sprite names
    final assetMap = _getAssetDataMap();
    if (assetMap == null) return;

    final List<String> allSpriteNames = [];
    assetMap.forEach((key, value) {
      if (value is TexturePackerAssetData) {
        allSpriteNames.addAll(value.frames.keys);
        allSpriteNames.addAll(value.animations.keys);
      }
    });
    
    if (allSpriteNames.isEmpty) {
      MachineToast.info("No sprites available. Link a .tpacker file in Map Properties.");
      return;
    }
    allSpriteNames.sort();

    // 2. Show Picker
    final selectedSprite = await showDialog<String>(
      context: context,
      builder: (ctx) => SpritePickerDialog(spriteNames: allSpriteNames),
    );

    if (selectedSprite == null) return;

    // 3. Get Dimensions
    final spriteData = _findSpriteDataInAssets(selectedSprite);
    if (spriteData == null) return; // Should not happen

    notifier?.beginObjectChange(_selectedLayerId);

    final newId = notifier!.map.nextObjectId ?? 1;
    final width = spriteData.sourceRect.width;
    final height = spriteData.sourceRect.height;

    // Center the sprite on the tap position (optional, or top-left)
    // Let's do Top-Left to match Tiled default, or center if that feels better.
    // Tiled usually places click at top-left.
    final x = _dragStartMapPosition!.dx;
    final y = _dragStartMapPosition!.dy;

    final newObject = TiledObject(
      id: newId,
      name: selectedSprite, // Auto-name the object
      x: x,
      y: y,
      width: width,
      height: height,
      properties: CustomProperties({
        'tp_sprite': Property(name: 'tp_sprite', type: PropertyType.string, value: selectedSprite)
      }),
    );

    layer.objects.add(newObject);
    notifier!.map.nextObjectId = newId + 1;
    notifier!.endObjectChange(_selectedLayerId);
    notifier!.selectObject(newObject);
    
    setState(() {});
  }

  void _handleObjectInteraction(Offset localPosition, {bool isStart = false}) {
    final layer = notifier?.map.layers.firstWhereOrNull((l) => l.id == _selectedLayerId);
    if (layer is! ObjectGroup) {
      if(isStart) {
        MachineToast.info("Select an Object Layer to edit objects.");
      }
      return;
    }

    final mapPosition = _getMapPosition(localPosition);

    switch (_activeObjectTool) {
      case ObjectTool.select:
        _handleSelectTool(mapPosition, isStart: isStart);
        break;
      case ObjectTool.move:
        _handleMoveTool(mapPosition, isStart: isStart);
        break;
      case ObjectTool.addRectangle:
      case ObjectTool.addEllipse:
      case ObjectTool.addPoint:
      case ObjectTool.addText:
        _handleCreateTool(mapPosition, isStart: isStart);
        break;
      case ObjectTool.addPolygon:
      case ObjectTool.addPolyline:
          _handlePolygonTool(mapPosition, isStart: isStart);
        break;
      case ObjectTool.addSprite:
        if (isStart) {
           // Capture the tap position. The picker logic runs in _handleObjectInteractionEnd.
           setState(() => _dragStartMapPosition = _snapOffsetToGrid(mapPosition));
        }
        break;
     }
  }

  void _handleObjectInteractionEnd() {
    // A small drag distance threshold to differentiate a tap from a drag.
    final dragThreshold = 4.0;
    final didDrag = _dragStartMapPosition != null &&
        (_getMapPosition(Offset.zero) - _dragStartMapPosition!).distance >
            dragThreshold;

    if (_activeObjectTool == ObjectTool.select && _marqueeSelection != null) {
      _selectObjectsInMarquee();
    } else if (_dragStartMapPosition != null) {
      switch (_activeObjectTool) {
        case ObjectTool.addRectangle:
        case ObjectTool.addEllipse:
        case ObjectTool.addPoint:
        case ObjectTool.addText:
          if (didDrag && _previewShape != null) {
            // It was a drag, create from preview
            _createShapeFromPreview();
          } else {
            // It was a tap, create a default-sized object
            _createShapeFromTap();
          }
          break;
        case ObjectTool.addSprite:
          if (!didDrag) {
            _createSpriteObjectFromTap();
          }
          break;
        case ObjectTool.addPolygon:
        case ObjectTool.addPolyline:
          // For poly tools, interaction end just finalizes the current point's position.
          // The shape itself is finalized by the "Finish Shape" button.
          // The logic is already handled by the last `_handlePolygonTool` call.
          break;
        default:
          break;
      }
    }

    if (_initialObjectPositions != null) {
      // Finalize move operation
      notifier?.endObjectChange(_selectedLayerId);
    }

    // Reset temporary drag state
    setState(() {
      _dragStartMapPosition = null;
      _previewShape = null;
      _marqueeSelection = null;
      _initialObjectPositions = null;
    });
  }

  TiledObject? _getObjectAt(Offset mapPosition, int layerId) {
    final layer =
        notifier?.map.layers.firstWhereOrNull((l) => l.id == layerId);
    if (layer is! ObjectGroup) return null;

    // Iterate backwards to hit top-most objects first
    for (final obj in layer.objects.reversed) {
      final rect = Rect.fromLTWH(obj.x, obj.y, obj.width, obj.height);
      if (rect.contains(mapPosition)) {
        return obj;
      }
    }
    return null;
  }

  void _handleSelectTool(Offset mapPosition, {required bool isStart}) {
    if (isStart) {
      final hitObject = _getObjectAt(mapPosition, _selectedLayerId);
      if (hitObject != null) {
        notifier?.selectObject(hitObject);
      } else {
        notifier?.clearSelection();
        setState(() {
          _dragStartMapPosition = mapPosition; // For marquee select
        });
      }
    } else {
      // Marquee select update
      if (_dragStartMapPosition == null) return;
      setState(() {
        // Use the new marqueeSelection state variable
        _marqueeSelection = Rect.fromPoints(_dragStartMapPosition!, mapPosition);
      });
    }
  }
  
    void _selectObjectsInMarquee() {
    final layer = notifier?.map.layers.firstWhereOrNull((l) => l.id == _selectedLayerId);
    if (layer is! ObjectGroup || _marqueeSelection == null) return;
    
    final selectionRect = _marqueeSelection!;
    final selected = <TiledObject>[];
    for (final obj in layer.objects) {
      final objRect = Rect.fromLTWH(obj.x, obj.y, obj.width, obj.height);
      if (selectionRect.overlaps(objRect)) {
        selected.add(obj);
      }
    }
    
    if (selected.isNotEmpty) {
      notifier?.selectObject(selected.first); // Select first
      for (var i = 1; i < selected.length; i++) {
        notifier?.addSelection(selected[i]); // Add rest to selection
      }
    }
  }

  void _handleMoveTool(Offset mapPosition, {required bool isStart}) {
    if (isStart) {
      if (notifier?.selectedObjects.isEmpty ?? true) return;
      // final hitObject = _getObjectAt(mapPosition, _selectedLayerId);
      // if (hitObject == null || !notifier!.selectedObjects.contains(hitObject)) {
      //   return;
      // }
      
      notifier?.beginObjectChange(_selectedLayerId);
      setState(() {
        _dragStartMapPosition = mapPosition;
        _initialObjectPositions = {
          for (var obj in notifier!.selectedObjects)
            obj.id: Point(x:obj.x, y:obj.y)
        };
      });
    } else {
      if (_dragStartMapPosition == null || _initialObjectPositions == null) return;
      
      var delta = mapPosition - _dragStartMapPosition!;
      if (_isSnapToGridEnabled) {
        delta = _snapOffsetToGrid(delta) - _snapOffsetToGrid(Offset.zero);
      }

      for (final obj in notifier!.selectedObjects) {
        final initialPos = _initialObjectPositions![obj.id];
        if (initialPos != null) {
          obj.x = initialPos.x + delta.dx;
          obj.y = initialPos.y + delta.dy;
        }
      }
      setState(() {}); // Trigger repaint
    }
  }

  void _handleCreateTool(Offset mapPosition, {required bool isStart}) {
    final snappedPos = _snapOffsetToGrid(mapPosition);
    if (isStart) {
      notifier?.beginObjectChange(_selectedLayerId);
      setState(() => _dragStartMapPosition = snappedPos);
    } else {
      if (_dragStartMapPosition == null) return;
      setState(() => _previewShape = Rect.fromPoints(_dragStartMapPosition!, snappedPos));
    }
  }

  void _createShapeFromTap() {
    final layer =
        notifier?.map.layers.firstWhereOrNull((l) => l.id == _selectedLayerId);
    if (layer is! ObjectGroup || _dragStartMapPosition == null) return;

    notifier?.beginObjectChange(_selectedLayerId);

    final defaultSize = _isSnapToGridEnabled
        ? Size(notifier!.map.tileWidth.toDouble(),
            notifier!.map.tileHeight.toDouble())
        : const Size(16, 16);
    
    final newId = notifier!.map.nextObjectId ?? 1;

    final newObject = TiledObject(
      id: newId,
      x: _dragStartMapPosition!.dx,
      y: _dragStartMapPosition!.dy,
      width: defaultSize.width,
      height: defaultSize.height,
    );

    _configureObjectShape(newObject);
    
    layer.objects.add(newObject);
    notifier!.map.nextObjectId = newId + 1;
    notifier!.endObjectChange(_selectedLayerId);
    notifier!.selectObject(newObject);
    
    setState(() {});
  }
  
  void _createShapeFromPreview() {
    final layer =
        notifier?.map.layers.firstWhereOrNull((l) => l.id == _selectedLayerId);
    if (layer is! ObjectGroup || _previewShape == null) return;

    // beginObjectChange was already called in _handleCreateTool
    
    final rect = _previewShape!;
    final newId = notifier!.map.nextObjectId ?? 1;

    final newObject = TiledObject(
      id: newId,
      x: rect.left,
      y: rect.top,
      width: rect.width.abs(),
      height: rect.height.abs(),
    );

    _configureObjectShape(newObject);
    
    layer.objects.add(newObject);
    notifier!.map.nextObjectId = newId + 1;
    notifier!.endObjectChange(_selectedLayerId);
    notifier!.selectObject(newObject);
    
    setState(() {});
  }

  void _configureObjectShape(TiledObject newObject) {
     switch (_activeObjectTool) {
      case ObjectTool.addRectangle:
        newObject.rectangle = true;
        break;
      case ObjectTool.addEllipse:
        newObject.ellipse = true;
        break;
      case ObjectTool.addText:
        newObject.text = tiled.Text(text: 'New Text');
        // Text objects are implicitly rectangular for their bounds
        newObject.rectangle = true;
        break;
      case ObjectTool.addPoint:
        newObject.point = true;
        break;
      default:
        // This function should only be called for shape tools
        break;
    }
  }

  void _handlePolygonTool(Offset mapPosition, {required bool isStart}) {
    final snappedPos = _snapOffsetToGrid(mapPosition);
    final point = Point(x: snappedPos.dx, y: snappedPos.dy);
    
    if (isStart) {
      if (_inProgressPoints.isEmpty) {
        // This is the very first point of a new shape
        notifier?.beginObjectChange(_selectedLayerId);
      }
      setState(() {
        // On tap down, add a new point to the list. This point will be updated on drag.
        _inProgressPoints.add(point);
      });
    } else {
      // This is a drag update (pan).
      if (_inProgressPoints.isNotEmpty) {
        setState(() {
          _inProgressPoints[_inProgressPoints.length - 1] = point;
        });
      }
    }
    syncCommandContext();
  }

  void _finalizePolygon() {
    final layer =
        notifier?.map.layers.firstWhereOrNull((l) => l.id == _selectedLayerId);
    if (layer is! ObjectGroup || _inProgressPoints.length < 2) {
      // Clear any stray points and exit
      setState(() {
        if (_inProgressPoints.isNotEmpty) {
          // No need to create a history entry if nothing was created.
          _inProgressPoints.clear();
        }
      });
      syncCommandContext();
      return;
    }

    // beginObjectChange was already called on the first tap.

    final newId = notifier!.map.nextObjectId ?? 1;
    final minX = _inProgressPoints.map((p) => p.x).reduce(min);
    final minY = _inProgressPoints.map((p) => p.y).reduce(min);
    final maxX = _inProgressPoints.map((p) => p.x).reduce(max);
    final maxY = _inProgressPoints.map((p) => p.y).reduce(max);

    final relativePoints = _inProgressPoints
        .map((p) => Point(x: p.x - minX, y: p.y - minY))
        .toList();

    // CORRECTED: Set the object's position to the top-left of the AABB,
    // and set its width and height.
    final newObject = TiledObject(
      id: newId,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
    );

    if (_activeObjectTool == ObjectTool.addPolygon) {
      newObject.polygon = relativePoints;
    } else {
      newObject.polyline = relativePoints;
    }

    layer.objects.add(newObject);
    notifier!.map.nextObjectId = newId + 1;
    notifier!.endObjectChange(_selectedLayerId);
    notifier!.selectObject(newObject);

    setState(() => _inProgressPoints.clear());
    syncCommandContext();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadingError != null)
      return Center(child: Text('Error loading map: $_loadingError'));
    if (notifier == null)
      return const Center(child: Text('Could not load map.'));
    final tiledSettings = ref.watch(effectiveSettingsProvider.select((s) => s.pluginSettings[TiledEditorSettings] as TiledEditorSettings?)) ?? TiledEditorSettings();

    final map = notifier!.map;
    final mapPixelWidth = (map.width * map.tileWidth).toDouble();
    final mapPixelHeight = (map.height * map.tileHeight).toDouble();

    final AsyncValue<Map<String, AssetData>> assetMapAsync =
        ref.watch(assetMapProvider(widget.tab.id));

    return assetMapAsync.when(
      skipLoadingOnReload: true,
      data: (assetDataMap) {
        final editorContent = GestureDetector(
          onTapDown: (details) =>
              _onInteractionUpdate(details.localPosition, isStart: true),
          onPanStart: (details) =>
              _onInteractionUpdate(details.localPosition, isStart: true),
          onPanUpdate: (details) => _onInteractionUpdate(details.localPosition),
          onPanEnd: (details) => _onInteractionEnd(),
          onTapUp: (details) => _onInteractionEnd(),
          onTapCancel: _onInteractionCancel,
          child: InteractiveViewer(
            clipBehavior: Clip.none,
            transformationController: _transformationController,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.1,
            maxScale: 16.0,
            panEnabled: isZoomMode,
            scaleEnabled: isZoomMode,
            child: CustomPaint(
              size: Size(mapPixelWidth, mapPixelHeight),
              painter: TiledMapPainter(
                map: map,
                assetDataMap: assetDataMap,
                tmxToProjectPaths: _tmxToProjectPaths,
                showGrid: _showGrid,
                transform: _transformationController.value,
                selectedObjects: notifier!.selectedObjects,
                previewShape: _previewShape,
                inProgressPoints: _inProgressPoints,
                marqueeSelection: _mode == TiledEditorMode.paint ? _tileMarqueeSelection : _marqueeSelection,
                settings: tiledSettings,
                floatingSelection: notifier!.floatingSelection,
                floatingSelectionPosition: notifier!.floatingSelectionPosition,
              ),
            ),
          ),
        );
    
        return Stack(
          fit: StackFit.expand,
          children: [
            editorContent,
            Positioned(
              top: 8,
              right: 8,
              child: Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: const CommandToolbar(
                      position: TiledEditorPlugin.tiledFloatingToolbar,
                    ),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              bottom: _isPaletteVisible ? 0 : -_paletteHeight,
              left: 0,
              right: 0,
              child: SizedBox(
                height: _paletteHeight,
                child: TilePalette(
                  map: notifier!.map,
                  assetDataMap: assetDataMap, 
                  selectedTileset: _selectedTileset,
                  selectedTileRect: _selectedTileRect,
                  onTilesetChanged: (ts) => setState(() => _selectedTileset = ts),
                  onTileSelectionChanged:
                      (rect) => setState(() => _selectedTileRect = rect),
                  onAddTileset: _addTileset,
                  onResize: _handlePaletteResize,
                  onInspectSelectedTileset: _inspectSelectedTileset,
                  onDeleteSelectedTileset: _deleteSelectedTileset,
                  onClearUnusedTilesets: _clearUnusedTilesets,
                ),
              ),
            ),
            // --- UPDATED LAYERS PANEL POSITIONING ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              top: 0,
              bottom: 0,
              left: _isLayersPanelVisible ? 0 : -320,
              width: 320,
              child: LayersPanel(
                layers: notifier!.map.layers,
                selectedLayerId: _selectedLayerId,
                selectedObjects: notifier!.selectedObjects,
                onLayerSelected: _onLayerSelect,
                onObjectSelected: (obj) {
                  setState(() {
                    _mode = TiledEditorMode.object;
                  });
                  notifier!.selectObject(obj);
                  syncCommandContext();
                },
                // Visibility
                onLayerVisibilityChanged: (id) => notifier!.toggleLayerVisibility(id),
                onObjectVisibilityChanged: (layerId, objectId) => 
                    notifier!.toggleObjectVisibility(layerId, objectId),
                
                // Reorder
                onLayerReorder: (oldIndex, newIndex) {
                  notifier!.reorderLayer(oldIndex, newIndex);
                },
                onObjectReorder: (layerId, oldIndex, newIndex) {
                  notifier!.reorderObject(layerId, oldIndex, newIndex);
                },
                
                onAddLayer: _addLayer,
                
                // Delete
                onLayerDelete: _deleteLayer,
                onObjectDelete: (layerId, objectId) {
                  notifier!.deleteObject(layerId, objectId);
                },
                
                // Inspect
                onLayerInspect: _showLayerInspector,
                onObjectInspect: _inspectObject,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Error loading assets:\n$err', textAlign: TextAlign.center),
        ),
      ),
    );
  }

  @override
  void undo() {
    _notifier?.undo();
    syncCommandContext();
  }

  @override
  void redo() {
    _notifier?.redo();
    syncCommandContext();
  }

  // ... (Other override methods are unchanged) ...
  @override
  Future<EditorContent> getContent() async {
    if (notifier == null) throw Exception("Map is not loaded");
    final writer = TmxWriter(notifier!.map);
    final newTmxContent = writer.toTmx();
    return EditorContentString(newTmxContent);
  }

  @override
  void onSaveSuccess(String newHash) {
    if (mounted) setState(() => _baseContentHash = newHash);
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async => null;
}
