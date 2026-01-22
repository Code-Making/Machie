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
import 'package:machine/logs/logs_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';
import '../flow_graph/flow_graph_parameter_parser.dart';

class TiledAssetResolver {
  final Map<String, AssetData> _assets;
  final ProjectRepository _repo;
  final String _tmxPath;
  final Talker? _talker;

  // New cache for flow graph parameters
  final Map<String, List<FlowGraphParameter>> _fgParamCache = {};

  TiledAssetResolver(this._assets, this._repo, this._tmxPath, [this._talker]);

  Map<String, AssetData> get rawAssets => _assets;
  String get tmxPath => _tmxPath;
  ProjectRepository get repo => _repo;

  // New method to asynchronously load and cache parameters
  Future<void> loadAndCacheFlowGraphParameters(String? relativeFgPath) async {
    // === FIX START ===
    if (relativeFgPath == null || relativeFgPath.isEmpty) {
      // Nothing to load if the path is empty.
      return;
    }
    // === FIX END ===

    final canonicalKey = _repo.resolveRelativePath(_tmxPath, relativeFgPath);

    // Avoid re-fetching if already in cache
    if (_fgParamCache.containsKey(canonicalKey)) {
      return;
    }

    try {
      final file = await _repo.fileHandler.resolvePath(_repo.rootUri, canonicalKey);
      if (file != null) {
        final content = await _repo.readFile(file.uri);
        final params = FlowGraphParameterParser.parse(content);
        _fgParamCache[canonicalKey] = params;
      } else {
        throw Exception("File not found at '$canonicalKey'");
      }
    } catch (e, st) {
      _talker?.handle(e, st, "Failed to load/parse flow graph parameters from '$relativeFgPath'");
      // Cache an empty list on failure to prevent re-fetching constantly
      _fgParamCache[canonicalKey] = [];
    }
  }

  // New synchronous method to get cached parameters
  List<FlowGraphParameter> getCachedFlowGraphParameters(String? relativeFgPath) {
    if (relativeFgPath == null || relativeFgPath.isEmpty) {
      return [];
    }
    final canonicalKey = _repo.resolveRelativePath(_tmxPath, relativeFgPath);
    return _fgParamCache[canonicalKey] ?? [];
  }
  
  // New method to clear cache when inspector is closed
  void clearFlowGraphParameterCache() {
    _fgParamCache.clear();
  }


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
    }
    
    return null;
  }

  TexturePackerSpriteData? _findSpriteInAtlases(String spriteName, Iterable<String> tpackerPaths) {
    for (final path in tpackerPaths) {
      final canonicalKey = _repo.resolveRelativePath(_tmxPath, path);
      final asset = getAsset(canonicalKey);

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

final tiledAssetResolverProvider = Provider.family.autoDispose<AsyncValue<TiledAssetResolver>, String>((ref, tabId) {
  final assetMapAsync = ref.watch(assetMapProvider(tabId));
  final repo = ref.watch(projectRepositoryProvider);
  final project = ref.watch(currentProjectProvider);
  final metadata = ref.watch(tabMetadataProvider)[tabId];
  final talker = ref.watch(talkerProvider);

  return assetMapAsync.whenData((assetMap) {
    if (repo == null || project == null || metadata == null) {
      throw Exception("Project context not available");
    }
    
    final tmxPath = repo.fileHandler.getPathForDisplay(metadata.file.uri, relativeTo: project.rootUri);
    return TiledAssetResolver(assetMap, repo, tmxPath, talker);
  });
});