// FILE: lib/editor/plugins/tiled_editor/tiled_export_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/tmj_writer.dart';
import 'package:machine/editor/plugins/tiled_editor/tmx_writer.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:tiled/tiled.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/utils/texture_packer_algo.dart';

import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/flow_graph/services/flow_export_service.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';
import 'package:machine/editor/plugins/flow_graph/flow_graph_asset_resolver.dart';

import 'tiled_asset_resolver.dart';
import 'project_tsx_provider.dart';

final tiledExportServiceProvider = Provider<TiledExportService>((ref) {
  return TiledExportService(ref);
});

class _UnifiedAssetSource {
  final String uniqueId;
  final ui.Image sourceImage;
  final ui.Rect sourceRect;
  final int width;
  final int height;

  _UnifiedAssetSource({
    required this.uniqueId,
    required this.sourceImage,
    required this.sourceRect,
  }) : width = sourceRect.width.toInt(),
       height = sourceRect.height.toInt();

  @override
  bool operator ==(Object other) => other is _UnifiedAssetSource && other.uniqueId == uniqueId;
  @override
  int get hashCode => uniqueId.hashCode;
}

class _UnifiedPackResult {
  final Uint8List atlasImageBytes;
  final int atlasWidth;
  final int atlasHeight;
  final int columns;
  final Map<String, ui.Rect> packedRects;
  final Map<String, int> idToGid;

  _UnifiedPackResult({
    required this.atlasImageBytes,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.columns,
    required this.packedRects,
    required this.idToGid,
  });
}

class _ExportContext {
  /// Canonical paths of maps already queued or processed to prevent cycles.
  final Set<String> visitedMaps = {};
  
  /// Canonical paths of atlases already scanned to prevent double processing
  final Set<String> visitedAtlases = {};
  
  /// Queue of map paths to process.
  final List<String> mapsToProcess = [];
  
  /// Aggregated unique assets from all maps.
  final Set<_UnifiedAssetSource> collectedAssets = {};
  
  /// Mapping from original project path to the final exported filename.
  /// Key: "libs/rooms/start.tmx", Value: "start.json"
  final Map<String, String> mapRenames = {};
  
  /// Cache of loaded TiledMap objects to avoid reading disk twice (scan phase & write phase).
  final Map<String, TiledMap> loadedMaps = {};
  
  final ProjectRepository repo;
  final Talker talker;

  _ExportContext(this.repo, this.talker);
}

class TiledExportService {
  final Ref _ref;
  TiledExportService(this._ref);

  static const int _flippedHorizontallyFlag = 0x80000000;
  static const int _flippedVerticallyFlag = 0x40000000;
  static const int _flippedDiagonallyFlag = 0x20000000;
  static const int _flagMask = _flippedHorizontallyFlag | _flippedVerticallyFlag | _flippedDiagonallyFlag;
  static const int _gidMask = ~_flagMask;

  int _getCleanGid(int gid) => gid & _gidMask;
  int _getGidFlags(int gid) => gid & _flagMask;

  int _nextPowerOfTwo(int v) {
    if (v <= 0) return 2;
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v++;
    return v;
  }

  Future<void> exportMap({
    required TiledMap map,
    required TiledAssetResolver resolver,
    required String destinationFolderUri,
    required String mapFileName,
    required String atlasFileName,
    bool removeUnused = true, 
    bool asJson = false,
    bool packInAtlas = true,
    bool packAssetsOnly = false,
    bool includeAllAtlasSprites = false,
    bool exportDependenciesAsJson = true,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    talker.info('Starting recursive map export: $mapFileName');

    final context = _ExportContext(repo, talker);

    // 1. Setup Root Map
    final rootPath = resolver.tmxPath;
    context.visitedMaps.add(rootPath);
    context.loadedMaps[rootPath] = map; // Use the live instance
    context.mapsToProcess.add(rootPath);

    final rootExtension = asJson ? 'json' : 'tmx';
    context.mapRenames[rootPath] = '$mapFileName.$rootExtension';

    // --- Recursive Discovery Loop ---
    while (context.mapsToProcess.isNotEmpty) {
      final currentMapPath = context.mapsToProcess.removeAt(0);

      await _scanMapDependencies(
        context: context,
        mapPath: currentMapPath,
        rootResolver: resolver,
        includeAllAtlasSprites: includeAllAtlasSprites,
        packInAtlas: packInAtlas,
        targetExtension: rootExtension,
      );
    }

    // --- Packing Phase ---
    _UnifiedPackResult? packResult;

    if (packInAtlas) {
      if (context.collectedAssets.isNotEmpty) {
        talker.info('Packing ${context.collectedAssets.length} unique assets from ${context.visitedMaps.length} maps (and linked atlases).');

        packResult = await _packUnifiedAtlasGrid(context.collectedAssets, map.tileWidth, map.tileHeight);

        talker.info('Atlas packing complete. Size: ${packResult.atlasWidth}x${packResult.atlasHeight}, Cols: ${packResult.columns}');

        await repo.createDocumentFile(
          destinationFolderUri,
          '$atlasFileName.png',
          initialBytes: packResult.atlasImageBytes,
          overwrite: true,
        );
        await repo.createDocumentFile(
          destinationFolderUri,
          '$atlasFileName.json',
          initialContent: _generatePixiJson(packResult, atlasFileName),
          overwrite: true,
        );
      } else {
        talker.info("No assets found to pack.");
      }
    }

    // --- Writing Phase ---
    if (!packAssetsOnly) {
      for (final entry in context.loadedMaps.entries) {
        final originalPath = entry.key;
        final mapInstance = _deepCopyMap(entry.value); 
        final exportName = context.mapRenames[originalPath]!;

        // Create specific resolver for this map context
        final mapResolver = TiledAssetResolver(
          resolver.rawAssets, 
          repo, 
          originalPath, 
          talker
        );

        // 1. Process Flow Graph Dependencies
        await _processFlowGraphDependencies(
          mapInstance,
          mapResolver,
          destinationFolderUri,
          exportAsJson: exportDependenciesAsJson,
        );

        if (packInAtlas && packResult != null) {
          // 2. Remap .tpacker references to exported JSON/tpacker files
          await _processTexturePackerDependencies(
            mapInstance,
            mapResolver,
            packResult,
            atlasFileName,
            destinationFolderUri,
            exportAsJson: exportDependenciesAsJson,
          );

          // 3. Remap Tilesets to the new Unified Atlas
          _remapAndFinalizeMap(mapInstance, packResult, atlasFileName);
        } else {
          // Legacy: Copy individual images
          await _copyAndRelinkAssets(mapInstance, mapResolver, destinationFolderUri);
        }

        // 4. Remap Links to other Maps (Properties pointing to .tmx files)
        _remapMapLinks(mapInstance, context, originalPath);

        // 5. Write Map File
        final fileContent = asJson ? TmjWriter(mapInstance).toTmj() : TmxWriter(mapInstance).toTmx();
        await repo.createDocumentFile(
          destinationFolderUri,
          exportName,
          initialContent: fileContent,
          overwrite: true,
        );
        talker.info('Exported map: $exportName');
      }
    } else {
      talker.info('Pack-only mode: Skipped generating map files.');
    }
    
    talker.info('Recursive export complete.');
  }

  // --- Scan Logic ---

  Future<void> _scanMapDependencies({
    required _ExportContext context,
    required String mapPath,
    required TiledAssetResolver rootResolver,
    required bool includeAllAtlasSprites,
    required bool packInAtlas,
    required String targetExtension,
  }) async {
    TiledMap map;

    // 1. Get Map Instance
    if (context.loadedMaps.containsKey(mapPath)) {
      map = context.loadedMaps[mapPath]!;
    } else {
      final file = await context.repo.fileHandler.resolvePath(context.repo.rootUri, mapPath);
      if (file == null) {
        context.talker.warning("Could not find linked map to process: $mapPath");
        return;
      }
      try {
        final content = await context.repo.readFile(file.uri);
        final parentUri = context.repo.fileHandler.getParentUri(file.uri);
        final tsxProvider = ProjectTsxProvider(context.repo, parentUri);
        final tsxProviders = await ProjectTsxProvider.parseFromTmx(content, tsxProvider.getProvider);

        map = TileMapParser.parseTmx(content, tsxList: tsxProviders);
        context.loadedMaps[mapPath] = map;

        final name = p.basenameWithoutExtension(mapPath);
        context.mapRenames[mapPath] = '$name.$targetExtension';
      } catch (e, st) {
        context.talker.handle(e, st, "Failed to parse linked map: $mapPath");
        return;
      }
    }

    // 2. Collect used assets
    if (packInAtlas) {
      final mapResolver = TiledAssetResolver(
        rootResolver.rawAssets,
        context.repo,
        mapPath,
        context.talker,
      );

      final assets = await _collectUnifiedAssets(
        map,
        mapResolver,
        // Disable individual inclusion logic here; handled separately in step 4
        includeAllAtlasSprites: false, 
      );
      context.collectedAssets.addAll(assets);
    }

    // 3. Find and queue linked maps
    _findAndQueueLinkedMaps(map, mapPath, context);

    // 4. Deep Scan of Linked Atlases
    if (includeAllAtlasSprites && packInAtlas) {
       await _findAndScanAtlases(map, mapPath, context);
    }
  }

  void _findAndQueueLinkedMaps(TiledMap map, String currentMapPath, _ExportContext context) {
    void checkProperties(CustomProperties properties) {
      for (final prop in properties) {
        String? potentialPath;

        if (prop.type == PropertyType.file && prop.value is String) {
          potentialPath = prop.value as String;
        } 
        else if (prop.type == PropertyType.string && prop.value is String) {
          final val = prop.value as String;
          if (val.toLowerCase().endsWith('.tmx')) {
            potentialPath = val;
          }
        }

        if (potentialPath != null && potentialPath.isNotEmpty) {
          final resolvedPath = context.repo.resolveRelativePath(currentMapPath, potentialPath);
          if (!context.visitedMaps.contains(resolvedPath)) {
            context.talker.debug("Found linked map: $resolvedPath (from $currentMapPath)");
            context.visitedMaps.add(resolvedPath);
            context.mapsToProcess.add(resolvedPath);
          }
        }
      }
    }

    checkProperties(map.properties);
    for (final layer in map.layers) {
      checkProperties(layer.properties);
    }
    _traverseMapObjects(map, (obj) {
      checkProperties(obj.properties);
    });
  }

  Future<void> _findAndScanAtlases(TiledMap map, String currentMapPath, _ExportContext context) async {
    final atlasesToScan = <String>{};

    void checkProperties(CustomProperties properties) {
      final atlasProp = properties['atlas'];
      if (atlasProp is StringProperty && atlasProp.value.isNotEmpty) {
        atlasesToScan.add(atlasProp.value);
      }
      final atlasesProp = properties['atlases'];
      if (atlasesProp is StringProperty && atlasesProp.value.isNotEmpty) {
        atlasesToScan.addAll(atlasesProp.value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
      }
    }

    checkProperties(map.properties);
    _traverseMapObjects(map, (obj) {
      checkProperties(obj.properties);
    });

    for (final relativePath in atlasesToScan) {
      await _scanTexturePackerFile(relativePath, currentMapPath, context);
    }
  }

  /// Loads a .tpacker file and extracts ALL its frames as assets.
  Future<void> _scanTexturePackerFile(
    String relativeTpackerPath,
    String mapContextPath,
    _ExportContext context,
  ) async {
    final repo = context.repo;
    final talker = context.talker;

    final tpackerCanonicalPath = repo.resolveRelativePath(mapContextPath, relativeTpackerPath);
    
    if (context.visitedAtlases.contains(tpackerCanonicalPath)) return;
    context.visitedAtlases.add(tpackerCanonicalPath);

    talker.debug('Deep scanning atlas for export: $tpackerCanonicalPath');

    try {
      // Use the AssetProvider system to load the TexturePacker asset properly.
      // This ensures we get the parsed TexturePackerAssetData with all path resolutions handled.
      final asset = await _ref.read(assetDataProvider(tpackerCanonicalPath).future);
      
      if (asset is TexturePackerAssetData) {
        talker.debug('Loaded atlas with ${asset.frames.length} frames.');
        
        // Iterate all frames in the atlas and add them to the unified assets list
        for (final entry in asset.frames.entries) {
          final frameName = entry.key;
          final spriteData = entry.value;
          final uniqueKey = 'sprite_$frameName';
          
          context.collectedAssets.add(_UnifiedAssetSource(
            uniqueId: uniqueKey,
            sourceImage: spriteData.sourceImage,
            sourceRect: spriteData.sourceRect,
          ));
        }
      } else {
        talker.warning('Loaded asset is not TexturePackerAssetData: $tpackerCanonicalPath');
      }
    } catch (e, st) {
      talker.handle(e, st, 'Failed to scan atlas file: $tpackerCanonicalPath');
    }
  }

  // --- Remapping Logic ---

  void _remapMapLinks(TiledMap map, _ExportContext context, String currentMapPath) {
    void updateProperties(CustomProperties props, Function(CustomProperties) setter) {
      if (props.isEmpty) return;
      
      final updates = <String, String>{};
      
      for (final prop in props) {
        if ((prop is StringProperty || prop is FileProperty) && prop.value is String) {
          final val = prop.value as String;
          if (val.isEmpty) continue;

          // Resolve property path to absolute
          final resolvedPath = context.repo.resolveRelativePath(currentMapPath, val);
          
          if (context.mapRenames.containsKey(resolvedPath)) {
            final newFileName = context.mapRenames[resolvedPath]!;
            updates[prop.name] = newFileName;
          }
        }
      }

      if (updates.isNotEmpty) {
        final newMap = Map<String, Property<Object>>.from(props.byName);
        updates.forEach((key, newVal) {
          final old = newMap[key]!;
          if (old is FileProperty) {
            newMap[key] = FileProperty(name: key, value: newVal);
          } else {
            newMap[key] = StringProperty(name: key, value: newVal);
          }
        });
        setter(CustomProperties(newMap));
      }
    }

    updateProperties(map.properties, (p) => map.properties = p);

    void processLayers(List<Layer> layers) {
      for (final layer in layers) {
        updateProperties(layer.properties, (p) => layer.properties = p);
        if (layer is Group) {
          processLayers(layer.layers);
        }
      }
    }
    processLayers(map.layers);

    _traverseMapObjects(map, (obj) {
      updateProperties(obj.properties, (p) => obj.properties = p);
    });
  }

  // --- Existing Logic (Refactored) ---

  void _traverseMapObjects(TiledMap map, void Function(TiledObject) callback) {
    void visitLayer(Layer layer) {
      if (layer is Group) {
        for (final child in layer.layers) visitLayer(child);
      } else if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          callback(obj);
        }
      }
    }
    for (final layer in map.layers) {
      visitLayer(layer);
    }
  }

  Future<Set<_UnifiedAssetSource>> _collectUnifiedAssets(
    TiledMap map, 
    TiledAssetResolver resolver,
    {bool includeAllAtlasSprites = false}
  ) async {
    final talker = _ref.read(talkerProvider);
    final assets = <_UnifiedAssetSource>{};
    final seenKeys = <String>{};
    
    // We'll collect all paths here to possibly scan later, or to look up animation frames
    final referencedAtlases = <String>{};

    void addAsset(String key, ui.Image? image, ui.Rect srcRect) {
      if (image != null && !seenKeys.contains(key)) {
        seenKeys.add(key);
        assets.add(_UnifiedAssetSource(
          uniqueId: key,
          sourceImage: image,
          sourceRect: srcRect,
        ));
      }
    }

    void scanTileLayers(Layer layer) {
      if (layer is Group) {
        for (final child in layer.layers) scanTileLayers(child);
      } else if (layer is TileLayer && layer.tileData != null) {
        for (final row in layer.tileData!) {
          for (final gidData in row) {
            final rawGid = gidData.tile;
            final cleanGid = _getCleanGid(rawGid);
            if (cleanGid == 0) continue;

            final tileset = map.tilesetByTileGId(cleanGid);
            if (tileset == null) continue;

            final localId = cleanGid - tileset.firstGid!;
            final uniqueKey = 'tile_${tileset.name}_$localId';

            if (!seenKeys.contains(uniqueKey)) {
              final tile = map.tileByGid(cleanGid);
              final imageSource = tile?.image?.source ?? tileset.image?.source;
              
              if (imageSource != null) {
                final image = resolver.getImage(imageSource, tileset: tileset);
                if (image != null) {
                  final rect = tileset.computeDrawRect(tile ?? Tile(localId: localId));
                  addAsset(uniqueKey, image, ui.Rect.fromLTWH(
                    rect.left.toDouble(),
                    rect.top.toDouble(),
                    rect.width.toDouble(),
                    rect.height.toDouble(),
                  ));
                }
              }
            }
          }
        }
      }
    }
    for(final layer in map.layers) scanTileLayers(layer);

    _traverseMapObjects(map, (obj) {
      // 1. Tile Objects
      if (obj.gid != null) {
        final cleanGid = _getCleanGid(obj.gid!);
        if (cleanGid != 0) {
          final tileset = map.tilesetByTileGId(cleanGid);
          if (tileset != null) {
            final localId = cleanGid - tileset.firstGid!;
            final uniqueKey = 'tile_${tileset.name}_$localId';
            
            if (!seenKeys.contains(uniqueKey)) {
                final tile = map.tileByGid(cleanGid);
                final imageSource = tile?.image?.source ?? tileset.image?.source;
                if (imageSource != null) {
                  final image = resolver.getImage(imageSource, tileset: tileset);
                  if (image != null) {
                    final rect = tileset.computeDrawRect(tile ?? Tile(localId: localId));
                    addAsset(uniqueKey, image, ui.Rect.fromLTWH(
                      rect.left.toDouble(), 
                      rect.top.toDouble(), 
                      rect.width.toDouble(), 
                      rect.height.toDouble()
                    ));
                  }
                }
            }
          }
        }
      }
      
      // 2. Sprite Objects
      final atlasProp = obj.properties['atlas'];
      if (atlasProp is StringProperty && atlasProp.value.isNotEmpty) {
        referencedAtlases.add(atlasProp.value);
        
        final frameProp = obj.properties['initialFrame'] ?? obj.properties['initialAnim'];
        if (frameProp is StringProperty && frameProp.value.isNotEmpty) {
          final spriteName = frameProp.value;
          
          // Look up if this is a single sprite or an animation
          // If it's an animation, we want ALL frames.
          final spritesToAdd = <TexturePackerSpriteData>[];
          
          for (final path in [atlasProp.value]) {
            final canonicalKey = resolver.repo.resolveRelativePath(resolver.tmxPath, path);
            final asset = resolver.getAsset(canonicalKey);
            
            if (asset is TexturePackerAssetData) {
              // Case A: It's an animation
              if (asset.animations.containsKey(spriteName)) {
                final frameNames = asset.animations[spriteName]!;
                for (final frameName in frameNames) {
                  if (asset.frames.containsKey(frameName)) {
                    spritesToAdd.add(asset.frames[frameName]!);
                  }
                }
              } 
              // Case B: It's a single sprite
              else if (asset.frames.containsKey(spriteName)) {
                spritesToAdd.add(asset.frames[spriteName]!);
              }
            }
          }

          if (spritesToAdd.isNotEmpty) {
            for (final spriteData in spritesToAdd) {
              final uniqueKey = 'sprite_${spriteData.name}';
              addAsset(uniqueKey, spriteData.sourceImage, spriteData.sourceRect);
            }
          } else {
            talker.warning('Object ${obj.id}: Could not resolve sprite/anim "$spriteName" in atlas "${atlasProp.value}".');
          }
        }
      }
    });

    void scanImageLayers(Layer layer) {
      if (layer is Group) {
        for(final child in layer.layers) scanImageLayers(child);
      } else if (layer is ImageLayer && layer.image.source != null) {
        final image = resolver.getImage(layer.image.source);
        if (image != null) {
          addAsset(
            'image_layer_${layer.id}',
            image,
            ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())
          );
        } else {
          talker.warning('Could not find source image "${layer.image.source}" for Image Layer "${layer.name}"');
        }
      }
    }
    for(final layer in map.layers) scanImageLayers(layer);

    return assets;
  }
  
  String? _findNodeNameInTree(PackerItemNode node, String id) {
    if (node.id == id) return node.name;
    for (final child in node.children) {
      final name = _findNodeNameInTree(child, id);
      if (name != null) return name;
    }
    return null;
  }

  SourceImageConfig? _findSourceConfig(SourceImageNode node, String id) {
    if (node.id == id && node.type == SourceNodeType.image) return node.content;
    for (final child in node.children) {
      final res = _findSourceConfig(child, id);
      if (res != null) return res;
    }
    return null;
  }

  ui.Rect _calculatePixelRect(SourceImageConfig config, GridRect grid) {
    final s = config.slicing;
    final left = s.margin + grid.x * (s.tileWidth + s.padding);
    final top = s.margin + grid.y * (s.tileHeight + s.padding);
    final width = grid.width * s.tileWidth + (grid.width - 1) * s.padding;
    final height = grid.height * s.tileHeight + (grid.height - 1) * s.padding;
    return ui.Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }
  
  Future<_UnifiedPackResult> _packUnifiedAtlasGrid(Set<_UnifiedAssetSource> assets, int tileWidth, int tileHeight) async {
    final sortedAssets = assets.toList()..sort((a, b) {
       if (a.height != b.height) return b.height.compareTo(a.height);
       if (a.width != b.width) return b.width.compareTo(a.width);
       return a.uniqueId.compareTo(b.uniqueId);
    });

    double totalArea = 0;
    for(var a in sortedAssets) totalArea += (a.width * a.height);
    
    int potSize = _nextPowerOfTwo(sqrt(totalArea).ceil());
    if (potSize < 256) potSize = 256;
    
    int maxAssetWidth = sortedAssets.isEmpty ? 0 : sortedAssets.map((e) => e.width).reduce(max);
    if (potSize < maxAssetWidth) potSize = _nextPowerOfTwo(maxAssetWidth);

    int columns = potSize ~/ tileWidth;
    if (columns < 1) {
      potSize = _nextPowerOfTwo(tileWidth * sortedAssets.length);
      columns = potSize ~/ tileWidth;
    }

    int rows = (sortedAssets.length / columns).ceil();
    int neededHeight = rows * tileHeight;
    int potHeight = _nextPowerOfTwo(neededHeight);

    while (potHeight > potSize * 2) {
      potSize *= 2;
      columns = potSize ~/ tileWidth;
      rows = (sortedAssets.length / columns).ceil();
      neededHeight = rows * tileHeight;
      potHeight = _nextPowerOfTwo(neededHeight);
    }
    
    final List<List<bool>> grid = [];

    void ensureRows(int rowIndex) {
      while (grid.length <= rowIndex) {
        grid.add(List.filled(columns, false));
      }
    }

    bool checkFit(int c, int r, int wCells, int hCells) {
      ensureRows(r + hCells - 1);
      for (int y = 0; y < hCells; y++) {
        for (int x = 0; x < wCells; x++) {
          if (c + x >= columns) return false;
          if (grid[r + y][c + x]) return false;
        }
      }
      return true;
    }

    void markOccupied(int c, int r, int wCells, int hCells) {
      for (int y = 0; y < hCells; y++) {
        for (int x = 0; x < wCells; x++) {
          grid[r + y][c + x] = true;
        }
      }
    }

    final packedRects = <String, ui.Rect>{};
    final idToGid = <String, int>{};

    for (final asset in sortedAssets) {
      final wCells = (asset.width / tileWidth).ceil();
      final hCells = (asset.height / tileHeight).ceil();

      bool placed = false;
      int r = 0;
      
      while (!placed) {
        ensureRows(r + hCells); 
        for (int c = 0; c <= columns - wCells; c++) {
          if (checkFit(c, r, wCells, hCells)) {
            markOccupied(c, r, wCells, hCells);
            
            final px = (c * tileWidth).toDouble();
            final py = (r * tileHeight).toDouble();
            
            packedRects[asset.uniqueId] = ui.Rect.fromLTWH(px, py, asset.width.toDouble(), asset.height.toDouble());
            
            idToGid[asset.uniqueId] = (r * columns) + c + 1;
            
            placed = true;
            break;
          }
        }
        if (!placed) r++;
      }
    }

    int totalRows = grid.length;
    int finalNeededHeight = totalRows * tileHeight;
    int finalPotHeight = _nextPowerOfTwo(finalNeededHeight);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    for (final entry in packedRects.entries) {
      final id = entry.key;
      final destRect = entry.value;
      final asset = sortedAssets.firstWhere((a) => a.uniqueId == id);
      
      canvas.drawImageRect(asset.sourceImage, asset.sourceRect, destRect, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(potSize, finalPotHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) throw Exception('Failed to encode atlas image.');

    return _UnifiedPackResult(
      atlasImageBytes: byteData.buffer.asUint8List(),
      atlasWidth: potSize,
      atlasHeight: finalPotHeight,
      columns: columns,
      packedRects: packedRects,
      idToGid: idToGid,
    );
  }

  void _remapAndFinalizeMap(TiledMap map, _UnifiedPackResult result, String atlasName) {
    final newTiles = <Tile>[];
    
    final sortedKeys = result.idToGid.keys.toList()..sort();

    for (final uniqueId in sortedKeys) {
        final newGid = result.idToGid[uniqueId]!;
        final localId = newGid - 1;

        newTiles.add(Tile(
            localId: localId,
            properties: CustomProperties({
                'atlas_id': StringProperty(name: 'atlas_id', value: uniqueId),
            }),
        ));
    }
    newTiles.sort((a, b) => a.localId.compareTo(b.localId));
    
    final oldTilesets = List<Tileset>.from(map.tilesets);

    int safeColumns = 1;
    if (map.tileWidth > 0) {
      safeColumns = max(1, result.atlasWidth ~/ map.tileWidth);
    }

    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      tileWidth: map.tileWidth,
      tileHeight: map.tileHeight,
      tileCount: result.columns * (result.atlasHeight ~/ map.tileHeight),
      columns: safeColumns,
      image: TiledImage(source: '$atlasName.png', width: result.atlasWidth, height: result.atlasHeight),
    )..tiles = newTiles;

    _performSafeRemap(map, oldTilesets, result.idToGid, result.packedRects);

    map.tilesets..clear()..add(newTileset);
  }

  void _performSafeRemap(
    TiledMap map, 
    List<Tileset> oldTilesets, 
    Map<String, int> keyToNewGid,
    Map<String, ui.Rect> keyToRect,
  ) {
    Tileset? findTileset(int gid) {
      for (var i = oldTilesets.length - 1; i >= 0; i--) {
        if (oldTilesets[i].firstGid != null && oldTilesets[i].firstGid! <= gid) {
          return oldTilesets[i];
        }
      }
      return null;
    }

    void processLayer(Layer layer) {
      if (layer is Group) {
        for(final child in layer.layers) processLayer(child);
      } else if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final g = layer.tileData![y][x];
            final rawGid = g.tile;
            if (rawGid == 0) continue;

            final cleanGid = _getCleanGid(rawGid);
            final flags = _getGidFlags(rawGid);

            final oldTileset = findTileset(cleanGid);
            if (oldTileset != null) {
              final localId = cleanGid - oldTileset.firstGid!;
              final key = 'tile_${oldTileset.name}_$localId';

              if (keyToNewGid.containsKey(key)) {
                final newGid = keyToNewGid[key]! | flags;
                layer.tileData![y][x] = Gid(newGid, g.flips);
              } else {
                layer.tileData![y][x] = Gid.fromInt(0);
              }
            }
          }
        }
      } else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) {
            final rawGid = object.gid!;
            final cleanGid = _getCleanGid(rawGid);
            final flags = _getGidFlags(rawGid);
            
            final oldTileset = findTileset(cleanGid);
            if (oldTileset != null) {
              final localId = cleanGid - oldTileset.firstGid!;
              final key = 'tile_${oldTileset.name}_$localId';
              
              if (keyToNewGid.containsKey(key)) {
                object.gid = keyToNewGid[key]! | flags;
              }
            }
          }
        }
      }
    }

    for (final layer in map.layers) {
      processLayer(layer);
    }
  }

  String _generatePixiJson(_UnifiedPackResult result, String atlasName) {
    final frames = <String, dynamic>{};
    final sortedKeys = result.packedRects.keys.toList()..sort();

    for (final uniqueId in sortedKeys) {
      final rect = result.packedRects[uniqueId]!;
      frames[uniqueId] = {
        "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
        "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()},
        "anchor": {"x": 0.5, "y": 0.5}
      };
    }
    
    final jsonOutput = {
      "frames": frames,
      "meta": {
        "app": "Machine Editor - Unified Export",
        "version": "1.0",
        "image": "$atlasName.png",
        "format": "RGBA8888",
        "size": {"w": result.atlasWidth, "h": result.atlasHeight},
        "scale": "1"
      }
    };
    return const JsonEncoder.withIndent('  ').convert(jsonOutput);
  }

  Future<void> _processTexturePackerDependencies(
    TiledMap map, 
    TiledAssetResolver resolver, 
    _UnifiedPackResult packResult, 
    String atlasName, 
    String destinationFolderUri,
    {bool exportAsJson = true}
  ) async {
      final talker = _ref.read(talkerProvider);
      final repo = resolver.repo;
      
      final referencedAtlases = <String>{};

      if (map.properties.has('atlas')) {
        final val = map.properties.getValue<String>('atlas');
        if (val != null) referencedAtlases.addAll(val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
      } else if (map.properties.has('atlases')) {
        final val = map.properties.getValue<String>('atlases');
        if (val != null) referencedAtlases.addAll(val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
      }

      _traverseMapObjects(map, (obj) {
        if (obj.properties.has('atlas')) {
          final val = obj.properties.getValue<String>('atlas');
          if (val != null && val.isNotEmpty) referencedAtlases.add(val);
        }
      });

      final newAtlasPaths = <String, String>{};

      for(final path in referencedAtlases) {
          try {
              final canonicalKey = repo.resolveRelativePath(resolver.tmxPath, path);
              final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);
              if (file == null) {
                  talker.warning('Could not find linked .tpacker file: $path');
                  continue;
              }

              final exportNameBase = 'export_${p.basenameWithoutExtension(path)}';
              
              if (exportAsJson) {
                final content = await repo.readFile(file.uri);
                final originalProject = TexturePackerProject.fromJson(jsonDecode(content));

                final newSourceImage = SourceImageNode(
                    id: 'unified_atlas',
                    name: atlasName,
                    type: SourceNodeType.image,
                    content: SourceImageConfig(
                        path: '$atlasName.png',
                        slicing: const SlicingConfig(tileWidth: 1, tileHeight: 1, margin: 0, padding: 0),
                    ),
                );

                final newDefinitions = <String, PackerItemDefinition>{};
                originalProject.definitions.forEach((nodeId, def) {
                    if (def is SpriteDefinition) {
                        final node = _findNodeInTree(originalProject.tree, nodeId);
                        if (node != null) {
                            final key = 'sprite_${node.name}';
                            final rect = packResult.packedRects[key];
                            if (rect != null) {
                                newDefinitions[nodeId] = SpriteDefinition(
                                    sourceImageId: newSourceImage.id, 
                                    gridRect: GridRect(x: rect.left.toInt(), y: rect.top.toInt(), width: rect.width.toInt(), height: rect.height.toInt()),
                                );
                            }
                        }
                    } else {
                        newDefinitions[nodeId] = def;
                    }
                });

                final newProject = TexturePackerProject(
                    sourceImagesRoot: SourceImageNode(
                        id: 'root',
                        name: 'root',
                        type: SourceNodeType.folder,
                        children: [newSourceImage],
                    ), 
                    tree: originalProject.tree,
                    definitions: newDefinitions,
                );
                
                final newFilename = '$exportNameBase.json';
                newAtlasPaths[path] = newFilename;
                
                await repo.createDocumentFile(
                    destinationFolderUri, 
                    newFilename,
                    initialContent: jsonEncode(newProject.toJson()),
                    overwrite: true,
                );
              } else {
                final newFilename = '$exportNameBase.tpacker';
                newAtlasPaths[path] = newFilename;
                
                final bytes = await repo.readFileAsBytes(file.uri);
                await repo.createDocumentFile(
                  destinationFolderUri,
                  newFilename,
                  initialBytes: bytes,
                  overwrite: true,
                );
              }

          } catch (e, st) {
              talker.handle(e, st, 'Failed to process .tpacker dependency: $path');
          }
      }

      if (map.properties.has('atlas')) {
         final oldVals = map.properties.getValue<String>('atlas')!.split(',');
         final newVals = oldVals.map((v) => newAtlasPaths[v.trim()] ?? v.trim()).join(',');
         
         final newProps = Map<String, Property<Object>>.from(map.properties.byName);
         newProps['atlas'] = StringProperty(name: 'atlas', value: newVals);
         map.properties = CustomProperties(newProps);
      }

      _traverseMapObjects(map, (obj) {
         if (obj.properties.has('atlas')) {
           final oldVal = obj.properties.getValue<String>('atlas');
           if (oldVal != null && newAtlasPaths.containsKey(oldVal)) {
             final newProps = Map<String, Property<Object>>.from(obj.properties.byName);
             newProps['atlas'] = StringProperty(name: 'atlas', value: newAtlasPaths[oldVal]!);
             obj.properties = CustomProperties(newProps);
           }
         }
      });
  }
  
  PackerItemNode? _findNodeInTree(PackerItemNode node, String id) {
      if (node.id == id) return node;
      for (final child in node.children) {
          final found = _findNodeInTree(child, id);
          if (found != null) return found;
      }
      return null;
  }

  Future<void> _processFlowGraphDependencies(
    TiledMap mapToExport, 
    TiledAssetResolver resolver, 
    String destinationFolderUri,
    {bool exportAsJson = true}
  ) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    final flowService = _ref.read(flowExportServiceProvider);

    // Collect futures to await all exports
    final futures = <Future>[];

    _traverseMapObjects(mapToExport, (obj) {
      if (obj.properties.has('flowGraph')) {
        final propVal = obj.properties.getValue<String>('flowGraph');
        if (propVal != null && propVal.isNotEmpty) {
          futures.add(Future(() async {
            try {
              final fgCanonicalKey = repo.resolveRelativePath(resolver.tmxPath, propVal);
              final fgFile = await repo.fileHandler.resolvePath(repo.rootUri, fgCanonicalKey);
              if (fgFile == null) {
                talker.warning("Flow Graph file not found: $propVal");
                return;
              }
              
              final exportName = p.basenameWithoutExtension(fgFile.name);
              String newFileName;

              if (exportAsJson) {
                final content = await repo.readFile(fgFile.uri);
                final graph = FlowGraph.deserialize(content);
                final fgPath = repo.fileHandler.getPathForDisplay(fgFile.uri, relativeTo: repo.rootUri);
                final fgResolver = FlowGraphAssetResolver(resolver.rawAssets, repo, fgPath);
                
                newFileName = '$exportName.json';
                
                await flowService.export(
                  graph: graph,
                  resolver: fgResolver,
                  destinationFolderUri: destinationFolderUri,
                  fileName: exportName,
                  embedSchema: true,
                );
              } else {
                newFileName = '$exportName.fg';
                final bytes = await repo.readFileAsBytes(fgFile.uri);
                await repo.createDocumentFile(
                  destinationFolderUri,
                  newFileName,
                  initialBytes: bytes,
                  overwrite: true,
                );
              }
              
              final newProps = Map<String, Property<Object>>.from(obj.properties.byName);
              newProps['flowGraph'] = StringProperty(name: 'flowGraph', value: newFileName);
              obj.properties = CustomProperties(newProps);

            } catch (e) {
              talker.warning('Failed to export Flow Graph dependency "$propVal": $e');
            }
          }));
        }
      }
    });
    
    await Future.wait(futures);
  }

  Future<void> _copyAndRelinkAssets(TiledMap mapToExport, TiledAssetResolver resolver, String destinationFolderUri) async {
    final repo = resolver.repo;
    
    for (final tileset in mapToExport.tilesets) {
      if (tileset.image?.source != null) {
        final rawSource = tileset.image!.source!;
        final contextPath = (tileset.source != null) 
            ? repo.resolveRelativePath(resolver.tmxPath, tileset.source!) 
            : resolver.tmxPath;
        
        final canonicalKey = repo.resolveRelativePath(contextPath, rawSource);
        final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);

        if (file != null) {
          final bytes = await repo.readFileAsBytes(file.uri);
          await repo.createDocumentFile(
            destinationFolderUri,
            file.name,
            initialBytes: bytes,
            overwrite: true,
          );
          
          final oldImage = tileset.image!;
          tileset.image = TiledImage(source: file.name, width: oldImage.width, height: oldImage.height);
          tileset.source = null;
        }
      }
    }
    
    void processLayer(Layer layer) async {
      if (layer is Group) {
        for(final child in layer.layers) processLayer(child);
      } else if (layer is ImageLayer && layer.image.source != null) {
        final rawSource = layer.image.source!;
        final canonicalKey = repo.resolveRelativePath(resolver.tmxPath, rawSource);
        final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);
        if (file != null) {
          final bytes = await repo.readFileAsBytes(file.uri);
          await repo.createDocumentFile(
            destinationFolderUri,
            file.name,
            initialBytes: bytes,
            overwrite: true,
          );
          
          final oldImage = layer.image;
          layer.image = TiledImage(source: file.name, width: oldImage.width, height: oldImage.height);
        }
      }
    }
    for(final layer in mapToExport.layers) processLayer(layer);
  }

  TiledMap _deepCopyMap(TiledMap original) {
    final writer = TmxWriter(original);
    final tmxString = writer.toTmx();
    return TileMapParser.parseTmx(tmxString);
  }
}