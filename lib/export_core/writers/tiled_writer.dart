import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';
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
    
    // Fixed: await resolution before getting URI
    final resolvedFile = await repo.fileHandler.resolvePath(projectRoot, projectRelativePath);
    if (resolvedFile == null) throw Exception("Could not resolve file $projectRelativePath");
    final parentUri = repo.fileHandler.getParentUri(resolvedFile.uri);

    final tsxProvider = ProjectTsxProvider(repo, parentUri);
    final tsxList = await ProjectTsxProvider.parseFromTmx(xmlString, tsxProvider.getProvider);
    final map = tiled.TileMapParser.parseTmx(xmlString, tsxList: tsxList);

    // ... (Rest of logic remains the same as Phase 3) ...
    // Note: Re-pasting brevity due to length, ensure the logic from Phase 3 is here
    
    final atlasPage = atlasResult.pages[0];
    final atlasFileName = "atlas_0.png"; 
    
    final int mapTileW = map.tileWidth;
    final int mapTileH = map.tileHeight;
    final int atlasCols = atlasPage.width ~/ mapTileW;

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

    final mapNode = document.findAllElements('map').first;
    mapNode.children.removeWhere((node) => node is XmlElement && node.name.local == 'tileset');
    
    final newTilesetNode = newTilesetBuilder.buildDocument().rootElement.copy();
    mapNode.children.insert(0, newTilesetNode);

    final Map<int, int> gidRemap = {};

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

    final Set<int> distinctGids = {};
    for (var layer in map.layers) {
      if (layer is tiled.TileLayer && layer.tileData != null) {
        for (var row in layer.tileData!) {
          for (var g in row) if (g.tile != 0) distinctGids.add(g.tile);
        }
      }
    }

    for (int oldGid in distinctGids) {
      final assetId = await getIdFromGid(oldGid);
      if (assetId != null && atlasResult.lookup.containsKey(assetId)) {
        final loc = atlasResult.lookup[assetId]!;
        final gridX = loc.packedRect.left ~/ mapTileW;
        final gridY = loc.packedRect.top ~/ mapTileH;
        final newLocalId = (gridY * atlasCols) + gridX;
        
        gidRemap[oldGid] = newLocalId + 1; 
      }
    }

    for (final layerNode in mapNode.findAllElements('layer')) {
      final dataNode = layerNode.findElements('data').first;
      final encoding = dataNode.getAttribute('encoding');
      
      if (encoding == 'csv') {
        final oldCsv = dataNode.innerText.trim();
        final newCsv = oldCsv.split(',').map((s) {
          final raw = int.tryParse(s.trim()) ?? 0;
          
          const flipMask = 0xE0000000;
          final flags = raw & flipMask;
          final gidWithoutFlags = raw & ~flipMask;

          if (gidWithoutFlags == 0) return '0';

          if (gidRemap.containsKey(gidWithoutFlags)) {
            final newGid = gidRemap[gidWithoutFlags]!;
            return (newGid | flags).toString();
          } else {
            return '0';
          }
        }).join(',');
        
        dataNode.innerText = '\n$newCsv\n';
      }
    }

    return utf8.encode(document.toXmlString(pretty: true));
  }
}