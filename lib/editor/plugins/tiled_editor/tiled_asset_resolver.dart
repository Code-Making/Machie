import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/app/app_notifier.dart';
import '../../../project/project_settings_notifier.dart';
import 'package:machine/logs/logs_provider.dart'; // Import

class TiledAssetResolver {
  final Map<String, AssetData> _assets;
  final ProjectRepository _repo;
  final String _tmxPath;
  final Talker? _talker; // Add Talker

  TiledAssetResolver(this._assets, this._repo, this._tmxPath, [this._talker]); // Update constructor

  // ... (getters) ...
  Map<String, AssetData> get rawAssets => _assets;
  String get tmxPath => _tmxPath;
  ProjectRepository get repo => _repo;

  // ... (getImage) ...
  ui.Image? getImage(String? source, {Tileset? tileset}) {
    if (source == null || source.isEmpty) return null;

    String contextPath = _tmxPath;
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

  TexturePackerSpriteData? getSpriteDataForObject(TiledObject object, TiledMap map) {
    final frameProp = object.properties['initialFrame'] ?? object.properties['initialAnim'];
    
    // [DIAGNOSTIC] Log property state
    if (frameProp is! StringProperty || frameProp.value.isEmpty) {
      _talker?.debug("[Resolver] Object ${object.id}: initialFrame/Anim is empty or missing.");
      return null;
    }
    
    final spriteName = frameProp.value;
    final atlasProp = object.properties['atlas'];
    
    if (atlasProp is StringProperty && atlasProp.value.isNotEmpty) {
      _talker?.debug("[Resolver] Object ${object.id}: Looking for '$spriteName' in atlas '${atlasProp.value}'");
      return _findSpriteInAtlases(spriteName, [atlasProp.value]);
    } else {
      // ... tp_atlases logic ...
      final mapAtlasesProp = map.properties['tp_atlases'];
      if (mapAtlasesProp is StringProperty && mapAtlasesProp.value.isNotEmpty) {
        final tpackerFiles = mapAtlasesProp.value.split(',').map((e) => e.trim());
        return _findSpriteInAtlases(spriteName, tpackerFiles);
      }
    }
    
    return null;
  }

  TexturePackerSpriteData? _findSpriteInAtlases(String spriteName, Iterable<String> tpackerPaths) {
    for (final path in tpackerPaths) {
      final canonicalKey = _repo.resolveRelativePath(_tmxPath, path);
      final asset = getAsset(canonicalKey);

      // [DIAGNOSTIC] Log asset lookup
      if (asset == null) {
         _talker?.warning("[Resolver] Asset not found for key: '$canonicalKey' (Path: $path)");
      } else if (asset is! TexturePackerAssetData) {
         _talker?.warning("[Resolver] Asset at '$canonicalKey' is not TexturePackerAssetData. Type: ${asset.runtimeType}");
      }

      if (asset is TexturePackerAssetData) {
        if (asset.frames.containsKey(spriteName)) {
          return asset.frames[spriteName]!;
        }
        if (asset.animations.containsKey(spriteName)) {
          final firstFrameName = asset.animations[spriteName]!.firstOrNull;
          if (firstFrameName != null && asset.frames.containsKey(firstFrameName)) {
            return asset.frames[firstFrameName]!;
          }
        }
        _talker?.warning("[Resolver] Sprite '$spriteName' not found in atlas '$path'. Available frames: ${asset.frames.length}");
      }
    }
    return null;
  }
}

// Update Provider
final tiledAssetResolverProvider = Provider.family.autoDispose<AsyncValue<TiledAssetResolver>, String>((ref, tabId) {
  final assetMapAsync = ref.watch(assetMapProvider(tabId));
  final repo = ref.watch(projectRepositoryProvider);
  final project = ref.watch(currentProjectProvider);
  final metadata = ref.watch(tabMetadataProvider)[tabId];
  final talker = ref.watch(talkerProvider); // Get talker

  return assetMapAsync.whenData((assetMap) {
    if (repo == null || project == null || metadata == null) {
      throw Exception("Project context not available");
    }
    
    final tmxPath = repo.fileHandler.getPathForDisplay(metadata.file.uri, relativeTo: project.rootUri);
    return TiledAssetResolver(assetMap, repo, tmxPath, talker); // Pass talker
  });
});