// FILE: lib/editor/plugins/tiled_editor/tiled_asset_resolver.dart

import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/app/app_notifier.dart';
import '../../../project/project_settings_notifier.dart';

/// A wrapper around the raw AssetMap that handles Tiled-specific
/// path resolution logic (Contextual lookup for TMX vs TSX).
class TiledAssetResolver {
  final Map<String, AssetData> _assets;
  final ProjectRepository _repo;
  final String _tmxPath; // The project-relative path of the current map

  TiledAssetResolver(this._assets, this._repo, this._tmxPath);

  /// Exposes the raw asset map for widgets that need to iterate all assets (e.g. Sprite Picker).
  Map<String, AssetData> get rawAssets => _assets;
  
  /// Exposes the path of the current TMX file.
  String get tmxPath => _tmxPath;

  /// Exposes the repository for calculation operations.
  ProjectRepository get repo => _repo;

  /// Resolves and returns the image for a given [source] path.
  /// 
  /// If [tileset] is provided, logic determines if the source is relative
  /// to the map (embedded tileset) or an external TSX file.
  ui.Image? getImage(String? source, {Tileset? tileset}) {
    if (source == null || source.isEmpty) return null;

    String contextPath = _tmxPath;

    // If this image belongs to an external tileset, the image path is relative
    // to that TSX file, not the TMX.
    if (tileset?.source != null) {
      contextPath = _repo.resolveRelativePath(_tmxPath, tileset!.source!);
    }

    final canonicalKey = _repo.resolveRelativePath(contextPath, source);
    final asset = _assets[canonicalKey];

    if (asset is ImageAssetData) {
      return asset.image;
    }
    return null;
  }

  AssetData? getAsset(String canonicalKey) => _assets[canonicalKey];

  /// Resolves sprite data for a TiledObject based on its properties.
  /// It checks for an object-specific 'atlas' property first, then falls back
  /// to the map-level 'tp_atlases' property.
  TexturePackerSpriteData? getSpriteDataForObject(TiledObject object, TiledMap map) {
    // 1. Determine the sprite name from object properties.
    final frameProp = object.properties['initialFrame'] ?? object.properties['initialAnim'];
    if (frameProp is! StringProperty || frameProp.value.isEmpty) {
      return null;
    }
    final spriteName = frameProp.value;

    // 2. Determine which atlas files to search in.
    final atlasProp = object.properties['atlas'];
    if (atlasProp is StringProperty && atlasProp.value.isNotEmpty) {
      // Object has a specific atlas override.
      return _findSpriteInAtlases(spriteName, [atlasProp.value]);
    } else {
      // Fallback to map-level linked atlases.
      final mapAtlasesProp = map.properties['tp_atlases'];
      if (mapAtlasesProp is StringProperty && mapAtlasesProp.value.isNotEmpty) {
        final tpackerFiles = mapAtlasesProp.value.split(',').map((e) => e.trim());
        return _findSpriteInAtlases(spriteName, tpackerFiles);
      }
    }
    
    return null;
  }

  /// [NEW HELPER METHOD]
  /// Searches through a given list of .tpacker file paths to find a specific sprite.
  TexturePackerSpriteData? _findSpriteInAtlases(String spriteName, Iterable<String> tpackerPaths) {
    for (final path in tpackerPaths) {
      final canonicalKey = repo.resolveRelativePath(tmxPath, path);
      final asset = getAsset(canonicalKey);

      if (asset is TexturePackerAssetData) {
        // Check for a direct frame match
        if (asset.frames.containsKey(spriteName)) {
          return asset.frames[spriteName]!;
        }
        // Check if it's an animation name, and return the first frame
        if (asset.animations.containsKey(spriteName)) {
          final firstFrameName = asset.animations[spriteName]!.firstOrNull;
          if (firstFrameName != null && asset.frames.containsKey(firstFrameName)) {
            return asset.frames[firstFrameName]!;
          }
        }
      }
    }
    return null; // Not found in any of the provided atlases
  }
}

/// Provider that combines the Repo, the AssetMap, and the TMX location
/// into a single usable Resolver object.
final tiledAssetResolverProvider = Provider.family.autoDispose<AsyncValue<TiledAssetResolver>, String>((ref, tabId) {
  final assetMapAsync = ref.watch(assetMapProvider(tabId));
  final repo = ref.watch(projectRepositoryProvider);
  final project = ref.watch(currentProjectProvider);
  final metadata = ref.watch(tabMetadataProvider)[tabId];

  return assetMapAsync.whenData((assetMap) {
    if (repo == null || project == null || metadata == null) {
      throw Exception("Project context not available");
    }
    
    final tmxPath = repo.fileHandler.getPathForDisplay(metadata.file.uri, relativeTo: project.rootUri);
    return TiledAssetResolver(assetMap, repo, tmxPath);
  });
});