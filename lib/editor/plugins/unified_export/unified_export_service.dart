// FILE: lib/editor/plugins/unified_export/unified_export_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:tiled/tiled.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xml/xml.dart';

import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/tiled_asset_resolver.dart';
import 'package:machine/editor/plugins/tiled_editor/project_tsx_provider.dart';
import 'package:machine/editor/plugins/tiled_editor/tmj_writer.dart';
import 'package:machine/editor/plugins/tiled_editor/tmx_writer.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/utils/texture_packer_algo.dart';
// import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';

import 'unified_export_models.dart';
import '../../../asset_cache/asset_models.dart';

final unifiedExportServiceProvider = Provider((ref) => UnifiedExportService(ref));

class UnifiedExportService {
  final Ref _ref;
  UnifiedExportService(this._ref);

  /// Scans the file at [rootUri] and recursively finds all dependencies.
  /// 
  /// [rootUri] MUST be a valid SAF URI (content://...).
  Future<DependencyNode> scanDependencies(
    String rootUri, 
    ProjectRepository repo, 
    TiledAssetResolver resolver
  ) async {
    // Convert the start URI to a project-relative display path (e.g. "maps/level1.tmx")
    // This ensures our dependency graph uses clean, logical paths.
    final rootPath = repo.fileHandler.getPathForDisplay(rootUri, relativeTo: repo.rootUri);
    final visited = <String>{};
    
    return _scanRecursive(rootPath, repo, resolver, visited);
  }

  Future<DependencyNode> _scanRecursive(
    String path, 
    ProjectRepository repo, 
    TiledAssetResolver resolver,
    Set<String> visited
  ) async {
    if (visited.contains(path)) return _createNode(path, [], visited: true);
    visited.add(path);

    // Resolve the display path back to a SAF URI for reading
    final file = await repo.fileHandler.resolvePath(repo.rootUri, path);
    if (file == null) {
      // File missing
      return _createNode(path, []);
    }

    final ext = p.extension(path).toLowerCase();
    final children = <DependencyNode>[];
    
    try {
      if (ext == '.tmx') {
        final content = await repo.readFile(file.uri);
        // Use the file's parent URI for relative TSX resolution
        final parentUri = repo.fileHandler.getParentUri(file.uri);
        final tsxProvider = ProjectTsxProvider(repo, parentUri);
        final tsxProviders = await ProjectTsxProvider.parseFromTmx(content, tsxProvider.getProvider);
        
        final map = TileMapParser.parseTmx(content, tsxList: tsxProviders);

        for (final ts in map.tilesets) {
          final imgSource = ts.image?.source;
          if (imgSource != null) {
            // Determine context path for the image.
            // If it's an external tileset (ts.source != null), the image is relative to that TSX.
            // Otherwise, it's relative to the TMX (path).
            String contextPath = path;
            if (ts.source != null) {
              contextPath = repo.resolveRelativePath(path, ts.source!);
            }
            
            final assetPath = repo.resolveRelativePath(contextPath, imgSource);
            children.add(await _scanRecursive(assetPath, repo, resolver, visited));
          }
        }
        
        void scanProperties(CustomProperties props) async {
          final fgProp = props['flowGraph'];
          if (fgProp is StringProperty && fgProp.value.isNotEmpty) {
             final assetPath = repo.resolveRelativePath(path, fgProp.value);
             children.add(await _scanRecursive(assetPath, repo, resolver, visited));
          }
          final tpProp = props['tp_atlases'];
          if (tpProp is StringProperty && tpProp.value.isNotEmpty) {
            for(var atlasPath in tpProp.value.split(',')) {
               final assetPath = repo.resolveRelativePath(path, atlasPath.trim());
               children.add(await _scanRecursive(assetPath, repo, resolver, visited));
            }
          }
        }
        
        scanProperties(map.properties);
        for(var layer in map.layers) {
          scanProperties(layer.properties);
          if (layer is ObjectGroup) {
            for(var obj in layer.objects) scanProperties(obj.properties);
          }
        }

      } else if (ext == '.tpacker') {
        final content = await repo.readFile(file.uri);
        final project = TexturePackerProject.fromJson(jsonDecode(content));
        
        void scanSource(SourceImageNode node) async {
          if (node.type == SourceNodeType.image && node.content != null) {
             final assetPath = repo.resolveRelativePath(path, node.content!.path);
             children.add(await _scanRecursive(assetPath, repo, resolver, visited));
          }
          for(var c in node.children) scanSource(c);
        }
        scanSource(project.sourceImagesRoot);
      }
    } catch (e) {
      print("Scan error on $path: $e");
    }

    return _createNode(path, children);
  }

  DependencyNode _createNode(String path, List<DependencyNode> children, {bool visited = false}) {
    final ext = p.extension(path).toLowerCase();
    ExportNodeType type = ExportNodeType.unknown;
    if (ext == '.tmx') type = ExportNodeType.tmx;
    else if (ext == '.tpacker') type = ExportNodeType.tpacker;
    else if (ext == '.fg') type = ExportNodeType.flowGraph;
    else if (['.png', '.jpg', '.jpeg'].contains(ext)) type = ExportNodeType.image;

    return DependencyNode(
      sourcePath: path, // This is now a display path
      destinationPath: path,
      type: type,
      children: children,
      included: !visited,
    );
  }

  Future<ExportResult> buildAtlas(
    DependencyNode rootNode,
    TiledAssetResolver resolver,
    {int maxAtlasSize = 2048, bool stripUnused = true}
  ) async {
    final slices = <PackableSlice>[];
    final repo = resolver.repo;
    
    // We use a Set to avoid processing the same file multiple times in the dependency graph
    final processedPaths = <String>{};
    
    Future<void> processNode(DependencyNode node) async {
      if (processedPaths.contains(node.sourcePath) || !node.included) return;
      processedPaths.add(node.sourcePath);

      // Resolve SAF URI to read file
      final file = await repo.fileHandler.resolvePath(repo.rootUri, node.sourcePath);
      if (file == null) return;

      if (node.type == ExportNodeType.tpacker) {
        final content = await repo.readFile(file.uri);
        final proj = TexturePackerProject.fromJson(jsonDecode(content));
        
        void collectSprites(PackerItemNode itemNode) {
          if (itemNode.type == PackerItemType.sprite) {
            final def = proj.definitions[itemNode.id];
            if (def is SpriteDefinition) {
              final sourceConfig = _findSourceInTpacker(proj.sourceImagesRoot, def.sourceImageId);
              if (sourceConfig != null) {
                // Ensure asset is loaded. sourceConfig.path is relative to tpacker file.
                final imgPath = repo.resolveRelativePath(node.sourcePath, sourceConfig.path);
                final imgAsset = resolver.rawAssets[imgPath]; 
                
                if (imgAsset is ImageAssetData) {
                   final sliceRect = _calculateTpackerRect(sourceConfig, def.gridRect);
                   slices.add(PackableSlice(
                     id: itemNode.name, // Sprite Name
                     sourceImage: imgAsset.image,
                     sourceRect: sliceRect,
                     originalName: itemNode.name,
                   ));
                }
              }
            }
          }
          for(var c in itemNode.children) collectSprites(c);
        }
        collectSprites(proj.tree);

      } else if (node.type == ExportNodeType.tmx) {
        final content = await repo.readFile(file.uri);
        final parentUri = repo.fileHandler.getParentUri(file.uri);
        final tsxProvider = ProjectTsxProvider(repo, parentUri);
        final tsxProviders = await ProjectTsxProvider.parseFromTmx(content, tsxProvider.getProvider);
        final map = TileMapParser.parseTmx(content, tsxList: tsxProviders);

        for (final tileset in map.tilesets) {
          if (tileset.image?.source == null) continue;
          
          String contextPath = node.sourcePath;
          if (tileset.source != null) {
            contextPath = repo.resolveRelativePath(node.sourcePath, tileset.source!);
          }
              
          final imgPath = repo.resolveRelativePath(contextPath, tileset.image!.source!);
          final imgAsset = resolver.rawAssets[imgPath];

          if (imgAsset is ImageAssetData) {
             final cols = tileset.columns ?? 1;
             final count = tileset.tileCount ?? 0;
             final tsName = tileset.name ?? 'ts_${tileset.image!.source}';
             
             for(int i=0; i<count; i++) {
               final x = (i % cols) * (tileset.tileWidth! + tileset.spacing) + tileset.margin;
               final y = (i ~/ cols) * (tileset.tileHeight! + tileset.spacing) + tileset.margin;
               
               final sliceId = "${tsName}_$i";
               
               if (!slices.any((s) => s.id == sliceId)) {
                 slices.add(PackableSlice(
                   id: sliceId,
                   sourceImage: imgAsset.image,
                   sourceRect: ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), tileset.tileWidth!.toDouble(), tileset.tileHeight!.toDouble()),
                   originalName: sliceId,
                   isGridTile: true,
                   originalGid: tileset.firstGid! + i, 
                 ));
               }
             }
          }
        }
      }

      for (var c in node.children) await processNode(c);
    }

    await processNode(rootNode);

    // Sort slices by ID to ensure deterministic output
    slices.sort((a, b) => a.id.compareTo(b.id));

    final packerItems = slices.map((s) => PackerInputItem(
      width: s.sourceRect.width, 
      height: s.sourceRect.height, 
      data: s
    )).toList();

    final packer = MaxRectsPacker(padding: 2);
    final packedResult = packer.pack(packerItems);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    final packedRects = <String, ui.Rect>{};

    for(final item in packedResult.items) {
      final slice = item.data as PackableSlice;
      final destRect = ui.Rect.fromLTWH(item.x, item.y, item.width, item.height);
      canvas.drawImageRect(slice.sourceImage, slice.sourceRect, destRect, paint);
      packedRects[slice.id] = destRect;
    }

    final picture = recorder.endRecording();
    final atlasImage = await picture.toImage(packedResult.width.toInt(), packedResult.height.toInt());
    final pngBytes = (await atlasImage.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

    final frames = <String, dynamic>{};
    
    final sortedKeys = packedRects.keys.toList()..sort();
    
    for(final id in sortedKeys) {
      final rect = packedRects[id]!;
      frames[id] = {
        "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
        "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()}
      };
    }

    final meta = {
      "app": "Machine Unified Exporter",
      "version": "1.0",
      "image": "atlas.png",
      "size": {"w": packedResult.width.toInt(), "h": packedResult.height.toInt()},
      "scale": "1"
    };

    return ExportResult(
      atlases: [AtlasPage(
        width: packedResult.width.toInt(), 
        height: packedResult.height.toInt(), 
        pngBytes: pngBytes, 
        packedRects: packedRects
      )], 
      atlasMetaJson: {"frames": frames, "meta": meta},
      gidRemapTable: {},
    );
  }

  /// Writes the export to the [destinationUri].
  /// 
  /// [destinationUri] MUST be a valid SAF URI to a directory.
  Future<void> writeExport(
    DependencyNode rootNode,
    ExportResult exportData,
    String destinationUri,
    ProjectRepository repo,
    {bool exportAsJson = true}
  ) async {
    final processedPaths = <String>{};
    final atlasFileName = "atlas.png";
    final atlasJsonName = "atlas.json";

    // Write Atlas
    final atlasPage = exportData.atlases.first;
    await repo.createDocumentFile(
      destinationUri, 
      atlasFileName, 
      initialBytes: atlasPage.pngBytes, 
      overwrite: true
    );
    await repo.createDocumentFile(
      destinationUri, 
      atlasJsonName, 
      initialContent: jsonEncode(exportData.atlasMetaJson), 
      overwrite: true
    );

    final atlasTileset = _createAtlasTileset(exportData, atlasFileName);

    Future<void> writeNode(DependencyNode node) async {
      if (processedPaths.contains(node.sourcePath) || !node.included) return;
      processedPaths.add(node.sourcePath);

      final originalName = p.basenameWithoutExtension(node.sourcePath);
      final newExt = exportAsJson ? '.json' : p.extension(node.sourcePath);
      final newName = "$originalName$newExt";

      if (node.type == ExportNodeType.tmx) {
        // Resolve SAF URI to read
        final file = await repo.fileHandler.resolvePath(repo.rootUri, node.sourcePath);
        if (file == null) return;

        final content = await repo.readFile(file.uri);
        final parentUri = repo.fileHandler.getParentUri(file.uri);
        final tsxProvider = ProjectTsxProvider(repo, parentUri);
        final tsxProviders = await ProjectTsxProvider.parseFromTmx(content, tsxProvider.getProvider);
        
        final originalMap = TileMapParser.parseTmx(content, tsxList: tsxProviders);
        final mapToExport = _deepCopyMap(originalMap);

        final gidRemap = <int, int>{};
        
        for (final tileset in mapToExport.tilesets) {
           final firstGid = tileset.firstGid ?? 1;
           final tsName = tileset.name ?? 'ts_${tileset.image?.source}';
           final tileCount = tileset.tileCount ?? 0;
           
           for (int i = 0; i < tileCount; i++) {
             final oldGid = firstGid + i;
             final sliceId = "${tsName}_$i";
             
             final newTile = atlasTileset.tiles.firstWhereOrNull((t) => 
               t.properties['originalId']?.value == sliceId
             );
             
             if (newTile != null) {
               gidRemap[oldGid] = 1 + newTile.localId;
             }
           }
        }

        _remapGids(mapToExport, gidRemap);

        mapToExport.tilesets.clear();
        mapToExport.tilesets.add(atlasTileset);
        
        final String resultContent = exportAsJson 
            ? TmjWriter(mapToExport).toTmj()
            : TmxWriter(mapToExport).toTmx();
            
        await repo.createDocumentFile(
          destinationUri, 
          newName, 
          initialContent: resultContent, 
          overwrite: true
        );

      } 
      // Add other types like flowGraph processing if needed here

      for(var c in node.children) await writeNode(c);
    }

    await writeNode(rootNode);
  }

  Tileset _createAtlasTileset(ExportResult exportData, String atlasImageName) {
    final packedRects = exportData.atlases.first.packedRects;
    final sortedKeys = packedRects.keys.toList()..sort();
    
    final newTiles = <Tile>[];
    int localId = 0;

    for (final id in sortedKeys) {
      final rect = packedRects[id]!;
      // Fixed: Using properties.byName assignment or CustomProperties constructor
      final props = CustomProperties({});
      props.byName['originalId'] = StringProperty(name: 'originalId', value: id);
      props.byName['sourceRect'] = StringProperty(name: 'sourceRect', value: '${rect.left},${rect.top},${rect.width},${rect.height}');
      
      final tile = Tile(
        localId: localId,
        properties: props,
      );
      newTiles.add(tile);
      localId++;
    }

    final atlasWidth = exportData.atlases.first.width;
    final atlasHeight = exportData.atlases.first.height;

    return Tileset(
      name: 'Atlas',
      firstGid: 1,
      tileWidth: 16, 
      tileHeight: 16,
      tileCount: newTiles.length,
      columns: 0, 
      image: TiledImage(source: atlasImageName, width: atlasWidth, height: atlasHeight),
      tiles: newTiles,
    );
  }

  void _remapGids(TiledMap map, Map<int, int> gidRemap) {
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.tileData!.length; y++) {
          for (int x = 0; x < layer.tileData![y].length; x++) {
             final gid = layer.tileData![y][x];
             if (gid.tile != 0 && gidRemap.containsKey(gid.tile)) {
               layer.tileData![y][x] = Gid(gidRemap[gid.tile]!, gid.flips);
             }
          }
        }
      } else if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          if (obj.gid != null && gidRemap.containsKey(obj.gid)) {
            obj.gid = gidRemap[obj.gid!];
          }
        }
      }
    }
  }
  
  TiledMap _deepCopyMap(TiledMap original) {
    final writer = TmxWriter(original);
    final tmxString = writer.toTmx();
    return TileMapParser.parseTmx(tmxString);
  }

  SourceImageConfig? _findSourceInTpacker(SourceImageNode node, String id) {
    if (node.id == id && node.content != null) return node.content;
    for(var c in node.children) {
      final found = _findSourceInTpacker(c, id);
      if (found != null) return found;
    }
    return null;
  }

  ui.Rect _calculateTpackerRect(SourceImageConfig config, GridRect grid) {
    final s = config.slicing;
    final left = s.margin + grid.x * (s.tileWidth + s.padding);
    final top = s.margin + grid.y * (s.tileHeight + s.padding);
    final width = grid.width * s.tileWidth + (grid.width - 1) * s.padding;
    final height = grid.height * s.tileHeight + (grid.height - 1) * s.padding;
    return ui.Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }
}