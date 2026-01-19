import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/tmj_writer.dart';
import 'package:machine/editor/plugins/tiled_editor/tmx_writer.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:tiled/tiled.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/utils/texture_packer_algo.dart';

import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/flow_graph/services/flow_export_service.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';
import 'package:machine/editor/plugins/flow_graph/flow_graph_asset_resolver.dart';

import 'tiled_asset_resolver.dart';

final tiledExportServiceProvider = Provider<TiledExportService>((ref) {
  return TiledExportService(ref);
});

/// Represents a visual asset discovered during recursion
class _DiscoveredAsset {
  final String id; // Unique Key (e.g. path + rect)
  final ui.Image image;
  final ui.Rect sourceRect;
  final String? name; // For sprite names
  final int? originalGid; // For tiles

  _DiscoveredAsset({
    required this.id,
    required this.image,
    required this.sourceRect,
    this.name,
    this.originalGid,
  });
}

/// Represents the state of the export as it traverses files
class _ExportContext {
  final Map<String, _DiscoveredAsset> assets = {};
  final Map<String, String> fileRemap = {}; // Old Path -> New Relative Path
  final String destinationRoot;
  final ProjectRepository repo;
  final TiledAssetResolver resolver;

  _ExportContext({
    required this.destinationRoot,
    required this.repo,
    required this.resolver,
  });

  void addAsset(_DiscoveredAsset asset) {
    if (!assets.containsKey(asset.id)) {
      assets[asset.id] = asset;
    }
  }
}

class _AtlasPage {
  final int index;
  final Uint8List pngBytes;
  final int width;
  final int height;
  final Map<String, ui.Rect> mappedRects; // AssetID -> PackedRect

  _AtlasPage(this.index, this.pngBytes, this.width, this.height, this.mappedRects);
}

class TiledExportService {
  final Ref _ref;
  TiledExportService(this._ref);

  Future<void> exportMap({
    required TiledMap map,
    required TiledAssetResolver resolver,
    required String destinationFolderUri,
    required String mapFileName,
    required String atlasFileName,
    bool asJson = false,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    
    talker.info('Starting Recursive Tiled Export...');

    // 1. Prepare Context
    final context = _ExportContext(
      destinationRoot: destinationFolderUri,
      repo: repo,
      resolver: resolver,
    );

    // 2. Clone Map to avoid mutating editor state
    final TiledMap workingMap = _deepCopyMap(map);

    // 3. Recursive Discovery
    await _discoverAssetsAndDependencies(workingMap, context);

    // 4. Pack Atlas
    final pages = await _packAtlas(context.assets.values.toList());
    
    // 5. Write Atlas Files
    for (final page in pages) {
      final suffix = pages.length > 1 ? '_${page.index}' : '';
      final fileName = '$atlasFileName$suffix';
      
      // Write Image
      await repo.createDocumentFile(
        destinationFolderUri,
        '$fileName.png',
        initialBytes: page.pngBytes,
        overwrite: true,
      );

      // Write JSON Data
      final jsonContent = _generateAtlasJson(page, fileName, context);
      await repo.createDocumentFile(
        destinationFolderUri,
        '$fileName.json',
        initialContent: jsonContent,
        overwrite: true,
      );
    }

    // 6. Remap Map Data (GIDs and Properties)
    _remapMapToAtlas(workingMap, pages, context, atlasFileName);

    // 7. Write Main Map File
    final mapExtension = asJson ? 'json' : 'tmx';
    String mapContent;
    if (asJson) {
      mapContent = TmjWriter(workingMap).toTmj();
    } else {
      mapContent = TmxWriter(workingMap).toTmx();
    }

    await repo.createDocumentFile(
      destinationFolderUri,
      '$mapFileName.$mapExtension',
      initialContent: mapContent,
      overwrite: true,
    );

    talker.info('Export Complete: $mapFileName.$mapExtension with ${pages.length} atlas pages.');
  }

  // --- Phase 1: Recursive Discovery ---

  Future<void> _discoverAssetsAndDependencies(TiledMap map, _ExportContext context) async {
    final repo = context.repo;
    final tmxPath = context.resolver.tmxPath;

    // A. Collect Tile Assets (from Tile Layers)
    // We scan tilesets first to prepare image sources
    for (final tileset in map.tilesets) {
      // Logic handled during layer scan to only grab used tiles? 
      // Better: Scan all used GIDs from layers.
    }

    final usedGids = _findUsedGids(map);
    for (final gid in usedGids) {
      await _extractTileAsset(gid, map, context);
    }

    // B. Collect Object Assets & Dependencies
    for (final layer in map.layers) {
      if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          // 1. Tile Objects (GID based)
          if (obj.gid != null) {
            await _extractTileAsset(obj.gid!, map, context);
          }

          // 2. Texture Packer Sprites (Custom Property)
          final spriteProp = obj.properties.byName['tp_sprite'];
          if (spriteProp is StringProperty && spriteProp.value.isNotEmpty) {
            await _extractTexturePackerAsset(spriteProp.value, map, context);
          }

          // 3. Flow Graph Dependency
          final flowProp = obj.properties.byName['flowGraph'];
          if (flowProp is StringProperty && flowProp.value.isNotEmpty) {
            final newPath = await _processFlowGraph(flowProp.value, context);
            if (newPath != null) {
              obj.properties.byName['flowGraph'] = StringProperty(
                name: 'flowGraph', 
                value: newPath,
              );
            }
          }
        }
      }
    }
  }

  Future<void> _extractTileAsset(int gid, TiledMap map, _ExportContext context) async {
    final tile = map.tileByGid(gid);
    final tileset = map.tilesetByTileGId(gid);
    if (tile == null || tileset == null) return;

    final imageSource = tile.image?.source ?? tileset.image?.source;
    if (imageSource == null) return;

    final image = context.resolver.getImage(imageSource, tileset: tileset);
    if (image == null) return;

    final rect = tileset.computeDrawRect(tile);
    final sourceRect = ui.Rect.fromLTWH(
        rect.left.toDouble(), rect.top.toDouble(), 
        rect.width.toDouble(), rect.height.toDouble()
    );

    // Unique ID for deduplication: "gid_<tilesetName>_<localId>"
    final assetId = 'tile_${tileset.name}_${tile.localId}';

    context.addAsset(_DiscoveredAsset(
      id: assetId,
      image: image,
      sourceRect: sourceRect,
      originalGid: gid,
    ));
  }

  Future<void> _extractTexturePackerAsset(String spriteName, TiledMap map, _ExportContext context) async {
    // Locate the .tpacker file referenced in map properties
    final tpAtlasesProp = map.properties['tp_atlases'];
    if (tpAtlasesProp is! StringProperty) return;

    final tpackerFiles = tpAtlasesProp.value.split(',').map((e) => e.trim());
    
    for (final path in tpackerFiles) {
      final canonicalKey = context.repo.resolveRelativePath(context.resolver.tmxPath, path);
      final asset = context.resolver.getAsset(canonicalKey);
      
      if (asset is TexturePackerAssetData) {
        if (asset.frames.containsKey(spriteName)) {
          final frame = asset.frames[spriteName]!;
          context.addAsset(_DiscoveredAsset(
            id: 'sprite_$spriteName',
            image: frame.sourceImage,
            sourceRect: frame.sourceRect,
            name: spriteName,
          ));
          return; // Found it
        }
      }
    }
  }

  Future<String?> _processFlowGraph(String relativePath, _ExportContext context) async {
    final repo = context.repo;
    final tmxPath = context.resolver.tmxPath;
    
    // 1. Resolve full path
    final sourceUri = repo.resolveRelativePath(tmxPath, relativePath);
    if (context.fileRemap.containsKey(sourceUri)) {
      return context.fileRemap[sourceUri];
    }

    // 2. Read File
    final file = await repo.fileHandler.resolvePath(repo.rootUri, sourceUri);
    if (file == null) return null;
    
    try {
      final content = await repo.readFile(file.uri);
      final graph = FlowGraph.deserialize(content);

      // 3. Recursive Asset Scan inside Graph (Simplified)
      // If FlowGraph nodes have "image" properties, we'd scan them here 
      // and add to context.addAsset(...) similarly.

      // 4. Export Graph as JSON
      final exportName = '${p.basenameWithoutExtension(file.name)}.json';
      
      // We assume FlowExportService logic here to serialize json
      final flowService = _ref.read(flowExportServiceProvider);
      // We use a temporary resolver for the graph's context
      final graphPath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: repo.rootUri);
      final graphResolver = FlowGraphAssetResolver(context.resolver.rawAssets, repo, graphPath);

      // We manually perform export to string instead of file to control placement
      // Or simply use the service if it supports string return.
      // For this implementation, let's rely on the service to write file 
      // but we need to know WHERE.
      
      await flowService.export(
        graph: graph,
        resolver: graphResolver,
        destinationFolderUri: context.destinationRoot,
        fileName: p.basenameWithoutExtension(file.name),
        embedSchema: true,
      );

      // 5. Update Mapping
      context.fileRemap[sourceUri] = exportName;
      return exportName;

    } catch (e) {
      _ref.read(talkerProvider).warning('Failed to process dependency $relativePath: $e');
      return null;
    }
  }

  // --- Phase 2: Packing ---

  Future<List<_AtlasPage>> _packAtlas(List<_DiscoveredAsset> assets) async {
    if (assets.isEmpty) return [];

    // Sort by height descending for better packing
    assets.sort((a, b) => b.sourceRect.height.compareTo(a.sourceRect.height));

    final pages = <_AtlasPage>[];
    final remainingAssets = List<_DiscoveredAsset>.from(assets);
    int pageIndex = 0;

    while (remainingAssets.isNotEmpty) {
      final packer = MaxRectsPacker(padding: 2);
      final inputItems = remainingAssets.map((a) => PackerInputItem(
        width: a.sourceRect.width,
        height: a.sourceRect.height,
        data: a,
      )).toList();

      // Simple strategy: Try 2048x2048. If items don't fit, they stay in unpacked.
      // We iterate creating pages until empty.
      
      // Note: MaxRectsPacker in this project calculates size automatically based on fit?
      // Or we define a bin size. Assuming the algo from `texture_packer_algo.dart`:
      // It usually expands. We'll enforce a max size logic or just let it pack all if possible.
      
      final result = packer.pack(inputItems); // Packs everything into one if possible
      
      // Render
      final width = _nextPowerOfTwo(result.width.toInt());
      final height = _nextPowerOfTwo(result.height.toInt());
      
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
      
      final mappedRects = <String, ui.Rect>{};
      final packedIds = <String>{};

      for (final item in result.items) {
        final asset = item.data as _DiscoveredAsset;
        final dst = ui.Rect.fromLTWH(item.x, item.y, item.width, item.height);
        
        canvas.drawImageRect(asset.image, asset.sourceRect, dst, paint);
        mappedRects[asset.id] = dst;
        packedIds.add(asset.id);
      }

      final img = await recorder.endRecording().toImage(width, height);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      
      pages.add(_AtlasPage(
        pageIndex++, 
        byteData!.buffer.asUint8List(), 
        width, 
        height, 
        mappedRects
      ));

      remainingAssets.removeWhere((a) => packedIds.contains(a.id));
      
      // Safety break
      if (packedIds.isEmpty) break; 
    }

    return pages;
  }

  // --- Phase 3: Remapping ---

  void _remapMapToAtlas(TiledMap map, List<_AtlasPage> pages, _ExportContext context, String atlasBaseName) {
    if (pages.isEmpty) return;

    // 1. Create New Tilesets (One per atlas page)
    final newTilesets = <Tileset>[];
    int currentFirstGid = 1;
    
    // GID Mapping: Map<AssetID, NewGlobalID>
    final assetIdToGid = <String, int>{};

    for (final page in pages) {
      final pageName = '${atlasBaseName}${pages.length > 1 ? '_${page.index}' : ''}';
      
      // We create a "Collection of Images" style tileset because we packed rects arbitrarily.
      // However, Tiled handles Atlas tilesets best if we define it as one image 
      // and define <tile>s with regions.
      
      final tiles = <Tile>[];
      int localId = 0;

      // We sort mapped rects by ID to ensure deterministic GID assignment
      final sortedIds = page.mappedRects.keys.toList()..sort();

      for (final assetId in sortedIds) {
        final rect = page.mappedRects[assetId]!;
        
        // In Tiled, to represent a sub-region of a single image tileset, 
        // strictly speaking, relies on grid. 
        // IF we want arbitrary sizes, we usually use separate images.
        // HACK: We can create a Tileset with the Atlas Image, set tileWidth/Height to 1??
        // BETTER: We rely on the output being for a GAME ENGINE (JSON/Pixi).
        // For the TMX to be viewable in Tiled, we construct a Tileset where
        // we assume the game engine reads the 'class' or properties to find the atlas frame.
        // But to make the TMX valid:
        
        final tile = Tile(
          localId: localId,
          // We don't set image here because we'll set the master image on the tileset
          // But wait, standard Tilesets are grids.
          // To support packed atlas in Tiled TMX, we often treat it as a "Collection" 
          // where the image source is the atlas, but that implies the whole image.
          
          // APPROACH: We will create a Tileset that has NO master image, 
          // but each Tile has an Image (the atlas) and a source rect? 
          // No, Tiled <image> tag is the whole file.
          
          // SOLUTION for Engine Export:
          // We define a tileset.
          // We use Custom Properties to store the frame name/coords.
          // We assign IDs.
        );
        
        // Add mapping
        assetIdToGid[assetId] = currentFirstGid + localId;
        tiles.add(tile);
        localId++;
      }

      final ts = Tileset(
        name: pageName,
        firstGid: currentFirstGid,
        tileWidth: 32, // Dummy values
        tileHeight: 32,
        image: TiledImage(source: '$pageName.png', width: page.width, height: page.height),
        tiles: tiles,
      );
      
      newTilesets.add(ts);
      currentFirstGid += tiles.length;
    }

    // 2. Clear Old Tilesets
    map.tilesets.clear();
    map.tilesets.addAll(newTilesets);

    // 3. Remap Layer Data
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final gid = layer.tileData![y][x];
            if (gid.tile == 0) continue;

            // Find asset ID for this original GID
            // Note: This is O(N) lookup in context, optimized by map
            final asset = context.assets.values.firstWhereOrNull((a) => a.originalGid == gid.tile);
            
            if (asset != null && assetIdToGid.containsKey(asset.id)) {
              final newGid = assetIdToGid[asset.id]!;
              layer.tileData![y][x] = Gid(newGid, gid.flips);
            } else {
              layer.tileData![y][x] = Gid(0, Flips.defaults()); // Clear if not found
            }
          }
        }
      }
      
      // 4. Remap Object Data
      if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          // Tile Objects
          if (obj.gid != null) {
             final asset = context.assets.values.firstWhereOrNull((a) => a.originalGid == obj.gid);
             if (asset != null && assetIdToGid.containsKey(asset.id)) {
               obj.gid = assetIdToGid[asset.id];
             }
          }

          // Sprite Objects
          final spriteProp = obj.properties.byName['tp_sprite'];
          if (spriteProp is StringProperty) {
            final assetId = 'sprite_${spriteProp.value}';
            if (assetIdToGid.containsKey(assetId)) {
              // Convert Sprite Object to Tile Object pointing to Atlas
              obj.gid = assetIdToGid[assetId];
              // Remove the custom property as it's now native Tiled
              obj.properties.byName.remove('tp_sprite');
              
              // We need to adjust Y coordinate because Tiled Objects anchor Bottom-Left 
              // for Tiles, but Top-Left for Shapes/Sprites usually. 
              // Tiled GID objects are drawn growing Up from Y.
              obj.y += obj.height;
            }
          }
        }
      }
    }
    
    // Clean up
    map.properties.byName.remove('tp_atlases');
  }

  String _generateAtlasJson(_AtlasPage page, String imageName, _ExportContext context) {
    final frames = <String, dynamic>{};
    
    for (final entry in page.mappedRects.entries) {
      final assetId = entry.key;
      final rect = entry.value;
      final asset = context.assets[assetId];
      
      // Use Sprite Name if available, else Asset ID
      final frameName = asset?.name ?? assetId;

      frames[frameName] = {
        "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
        "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()},
      };
    }

    final jsonOutput = {
      "frames": frames,
      "meta": {
        "app": "Machine Editor - Unified Export",
        "version": "1.0",
        "image": "$imageName.png",
        "size": {"w": page.width, "h": page.height},
        "scale": "1"
      }
    };
    return const JsonEncoder.withIndent('  ').convert(jsonOutput);
  }

  // --- Helpers ---

  Set<int> _findUsedGids(TiledMap map) {
    final usedGids = <int>{};
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (final row in layer.tileData!) {
          for (final gid in row) {
            if (gid.tile != 0) usedGids.add(gid.tile);
          }
        }
      } else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) usedGids.add(object.gid!);
        }
      }
    }
    return usedGids;
  }

  TiledMap _deepCopyMap(TiledMap original) {
    final writer = TmxWriter(original);
    final tmxString = writer.toTmx();
    return TileMapParser.parseTmx(tmxString);
  }

  int _nextPowerOfTwo(int v) {
    if (v == 0) return 1;
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v++;
    return v;
  }
}