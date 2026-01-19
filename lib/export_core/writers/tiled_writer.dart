import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/project_tsx_provider.dart';
import 'package:tiled/tiled.dart' as tiled;
import '../packer/packer_models.dart';
import '../models.dart';
import 'writer_interface.dart';

class TiledAssetWriter implements AssetWriter {
  final ProjectRepository repo;
  final String projectRoot;

  TiledAssetWriter(this.repo, this.projectRoot);

  @override
  String get extension => 'tmx';

  @override
  Future<Uint8List> rewrite(
    String projectRelativePath,
    Uint8List fileContent,
    PackedAtlasResult atlasResult,
  ) async {
    final xmlString = utf8.decode(fileContent);
    final document = XmlDocument.parse(xmlString);
    
    // 1. Parse original map to understand geometry and tilesets
    // We need a helper here similar to Phase 1 to resolve tilesets
    final parentUri = repo.fileHandler.getParentUri(repo.fileHandler.resolvePath(projectRoot, projectRelativePath)!.uri);
    final tsxProvider = ProjectTsxProvider(repo, parentUri);
    final tsxList = await ProjectTsxProvider.parseFromTmx(xmlString, tsxProvider.getProvider);
    final map = tiled.TileMapParser.parseTmx(xmlString, tsxList: tsxList);

    // 2. Prepare the new "Atlas Tileset"
    // We assume Page 0 for simplicity in this implementation. 
    // Multi-page TMX requires multiple tileset definitions.
    final atlasPage = atlasResult.pages[0];
    final atlasFileName = "atlas_0.png"; 
    
    final int mapTileW = map.tileWidth;
    final int mapTileH = map.tileHeight;
    final int atlasCols = atlasPage.width ~/ mapTileW;

    // 3. Define the New Tileset Node
    final newTilesetBuilder = XmlBuilder();
    newTilesetBuilder.element('tileset', nest: () {
      newTilesetBuilder.attribute('firstgid', 1);
      newTilesetBuilder.attribute('name', 'PackedAtlas');
      newTilesetBuilder.attribute('tilewidth', mapTileW);
      newTilesetBuilder.attribute('tileheight', mapTileH);
      newTilesetBuilder.attribute('tilecount', (atlasPage.width ~/ mapTileW) * (atlasPage.height ~/ mapTileH));
      newTilesetBuilder.attribute('columns', atlasCols);
      
      newTilesetBuilder.element('image', nest: () {
        newTilesetBuilder.attribute('source', atlasFileName);
        newTilesetBuilder.attribute('width', atlasPage.width);
        newTilesetBuilder.attribute('height', atlasPage.height);
      });
    });

    // 4. Remove old tilesets and inject new one
    final mapNode = document.findAllElements('map').first;
    mapNode.children.removeWhere((node) => node is XmlElement && node.name.local == 'tileset');
    
    // Inject new tileset at the top
    final newTilesetNode = newTilesetBuilder.buildDocument().rootElement.copy();
    mapNode.children.insert(0, newTilesetNode);

    // 5. Build Remapping Lookup (Old GID -> New GID)
    // This requires iterating the ORIGINAL map's used tiles and finding where they went.
    final Map<int, int> gidRemap = {};

    // Helper to get Asset ID from GID
    Future<ExportableAssetId?> getIdFromGid(int gid) async {
      final tile = map.tileByGid(gid);
      final tileset = map.tilesetByTileGId(gid);
      if (tile == null || tileset == null) return null;
      
      String? rawSource = tile.image?.source ?? tileset.image?.source;
      if (rawSource == null) return null;

      String contextPath = projectRelativePath;
      if (tileset.source != null) {
        contextPath = repo.resolveRelativePath(projectRelativePath, tileset.source!);
      }
      final imagePath = repo.resolveRelativePath(contextPath, rawSource);
      final rect = tileset.computeDrawRect(tile);

      return ExportableAssetId(
        sourcePath: imagePath,
        x: rect.left.toInt(),
        y: rect.top.toInt(),
        width: rect.width.toInt(),
        height: rect.height.toInt(),
      );
    }

    // Pre-calculate mappings
    // (In a real app with thousands of tiles, this loop should be optimized to visit unique tilesets, not every tile)
    // For now, we iterate layers -> data -> gids
    final Set<int> distinctGids = {};
    for (var layer in map.layers) {
      if (layer is tiled.TileLayer && layer.tileData != null) {
        for (var row in layer.tileData!) {
          for (var g in row) if (g.tile != 0) distinctGids.add(g.tile);
        }
      }
      // TODO: Object groups GID handling
    }

    for (int oldGid in distinctGids) {
      final assetId = await getIdFromGid(oldGid);
      if (assetId != null && atlasResult.lookup.containsKey(assetId)) {
        final loc = atlasResult.lookup[assetId]!;
        
        // Calculate New GID based on Grid Position in Atlas
        // Formula: (y / tileH) * cols + (x / tileW)
        // Add 1 because Tiled GIDs are 1-based (0 is empty)
        // We add `firstgid` of the new tileset (which is 1)
        final gridX = loc.packedRect.left ~/ mapTileW;
        final gridY = loc.packedRect.top ~/ mapTileH;
        final newLocalId = (gridY * atlasCols) + gridX;
        
        gidRemap[oldGid] = newLocalId + 1; // +1 for FirstGid
      }
    }

    // 6. Rewrite Layer Data
    for (final layerNode in mapNode.findAllElements('layer')) {
      final dataNode = layerNode.findElements('data').first;
      final encoding = dataNode.getAttribute('encoding');
      
      if (encoding == 'csv') {
        final oldCsv = dataNode.innerText.trim();
        final newCsv = oldCsv.split(',').map((s) {
          final raw = int.tryParse(s.trim()) ?? 0;
          
          // Handle Flips (Tiled stores flips in high bits)
          const flipMask = 0xE0000000; // Horiz, Vert, Diag
          final flags = raw & flipMask;
          final gidWithoutFlags = raw & ~flipMask;

          if (gidWithoutFlags == 0) return '0';

          if (gidRemap.containsKey(gidWithoutFlags)) {
            final newGid = gidRemap[gidWithoutFlags]!;
            return (newGid | flags).toString();
          } else {
            // If not found in atlas (maybe missed during collection?), keep 0 or handle error
            return '0';
          }
        }).join(',');
        
        dataNode.innerText = '\n$newCsv\n';
      } else {
        // TODO: Handle Base64/Zlib if necessary, or force CSV in settings
        print("Warning: Only CSV encoding supported for export currently.");
      }
    }

    return utf8.encode(document.toXmlString(pretty: true));
  }
}