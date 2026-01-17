import 'dart:ui' as ui;
import 'package:tiled/tiled.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../../asset_cache/asset_models.dart';

/// A bridge class that resolves Tiled's context-sensitive relative paths
/// into canonical keys for the generic [AssetMap].
class TiledAssetResolver {
  final ProjectRepository _repo;
  final Map<String, AssetData> _genericAssets;
  
  /// The canonical project-relative directory containing the TMX file.
  /// e.g. "maps/forest/"
  final String _tmxBaseDir;

  TiledAssetResolver({
    required ProjectRepository repo,
    required String tmxPath,
    required Map<String, AssetData> genericAssets,
  })  : _repo = repo,
        _genericAssets = genericAssets,
        _tmxBaseDir = repo.getDirectoryName(tmxPath);

  /// Retrieves the image asset for a [Tileset].
  /// Handles the complexity of external TSX files where the image path
  /// is relative to the TSX file, not the map file.
  AssetData? getTilesetImage(Tileset tileset) {
    final imageSource = tileset.image?.source;
    if (imageSource == null) return null;

    String canonicalKey;

    if (tileset.source != null) {
      // 1. External Tileset (.tsx)
      // The `tileset.source` is relative to the TMX file.
      final tsxPath = _repo.resolveRelativePath(_tmxBaseDir, tileset.source!);
      final tsxDir = _repo.getDirectoryName(tsxPath);
      
      // The `imageSource` is relative to that TSX file.
      canonicalKey = _repo.resolveRelativePath(tsxDir, imageSource);
    } else {
      // 2. Embedded Tileset
      // The `imageSource` is relative to the TMX file directly.
      canonicalKey = _repo.resolveRelativePath(_tmxBaseDir, imageSource);
    }

    return _genericAssets[canonicalKey];
  }

  /// Retrieves the image asset for an [ImageLayer].
  /// Image Layers are always embedded in the map, so paths are relative to the TMX.
  AssetData? getLayerImage(ImageLayer layer) {
    final imageSource = layer.image.source;
    if (imageSource == null) return null;

    final canonicalKey = _repo.resolveRelativePath(_tmxBaseDir, imageSource);
    return _genericAssets[canonicalKey];
  }

  /// Looks up a sprite by name from any loaded Texture Packer atlas.
  /// Since sprites are logical entities inside an asset, we search the loaded values.
  TexturePackerSpriteData? getSprite(String spriteName) {
    if (spriteName.isEmpty) return null;

    for (final asset in _genericAssets.values) {
      if (asset is TexturePackerAssetData) {
        if (asset.frames.containsKey(spriteName)) {
          return asset.frames[spriteName];
        }
        // Check animations (usually the first frame of the animation)
        if (asset.animations.containsKey(spriteName)) {
          final firstFrameName = asset.animations[spriteName]!.firstOrNull;
          if (firstFrameName != null && asset.frames.containsKey(firstFrameName)) {
            return asset.frames[firstFrameName];
          }
        }
      }
    }
    return null;
  }
}