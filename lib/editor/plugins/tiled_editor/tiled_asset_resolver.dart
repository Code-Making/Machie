

import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart';

import '../../../asset_cache/asset_models.dart';
import '../../../asset_cache/asset_providers.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../../logs/logs_provider.dart';
import '../../../project/project_settings_notifier.dart';
import '../../tab_metadata_notifier.dart';
import '../flow_graph/flow_graph_parameter_parser.dart';
import 'project_tsx_provider.dart';

class TiledAssetResolver {
  final Map<String, AssetData> _assets;
  final ProjectRepository _repo;
  final String _tmxPath;
  final Talker? _talker;

  // --- START: PHASE 1 IMPLEMENTATION ---

  /// A private cache to store the parsed parameters of a flow graph file.
  /// The key is the project-relative path to the .fg file.
  final Map<String, List<FlowGraphParameter>> _fgParamCache = {};
  final Map<String, TiledMap> _externalMapCache = {};
  final Map<String, TexturePackerSpriteData?> _resolvedSpriteCache = {};

  TiledAssetResolver(this._assets, this._repo, this._tmxPath, [this._talker]);

  Map<String, AssetData> get rawAssets => _assets;
  String get tmxPath => _tmxPath;
  ProjectRepository get repo => _repo;

  Future<TiledMap?> loadAndCacheExternalMap(String? relativeTmxPath) async {
    if (relativeTmxPath == null || relativeTmxPath.isEmpty) {
      return null;
    }

    final canonicalKey = _repo.resolveRelativePath(_tmxPath, relativeTmxPath);
    if (_externalMapCache.containsKey(canonicalKey)) {
      return _externalMapCache[canonicalKey];
    }

    try {
      final file = await _repo.fileHandler.resolvePath(
        _repo.rootUri,
        canonicalKey,
      );
      if (file != null) {
        final content = await _repo.readFile(file.uri);
        // We need a TsxProvider to parse maps that have external tilesets.
        final parentUri = _repo.fileHandler.getParentUri(file.uri);
        final tsxProvider = ProjectTsxProvider(_repo, parentUri);
        final tsxProviders = await ProjectTsxProvider.parseFromTmx(
          content,
          tsxProvider.getProvider,
        );
        final map = TileMapParser.parseTmx(content, tsxList: tsxProviders);
        _externalMapCache[canonicalKey] = map;
        return map;
      }
    } catch (e, st) {
      _talker?.handle(
        e,
        st,
        "Failed to load/parse external map: $relativeTmxPath",
      );
    }
    return null;
  }

  void clearExternalMapCache() {
    _externalMapCache.clear();
  }

  /// Loads the content of a .fg file, parses its input parameters,
  /// and stores the result in the cache.
  Future<void> loadAndCacheFlowGraphParameters(String? relativeFgPath) async {
    if (relativeFgPath == null || relativeFgPath.isEmpty) {
      return;
    }

    // Resolve the path relative to the TMX file to get a unique, project-wide key.
    final canonicalKey = _repo.resolveRelativePath(_tmxPath, relativeFgPath);

    // If it's already in the cache, we don't need to do anything.
    if (_fgParamCache.containsKey(canonicalKey)) {
      return;
    }

    try {
      // Resolve the full path and read the file content.
      final file = await _repo.fileHandler.resolvePath(
        _repo.rootUri,
        canonicalKey,
      );
      if (file != null) {
        final content = await _repo.readFile(file.uri);
        // Use the existing parser to get the parameters.
        final params = FlowGraphParameterParser.parse(content);
        // Store the result in the cache.
        _fgParamCache[canonicalKey] = params;
      } else {
        throw Exception("File not found at '$canonicalKey'");
      }
    } catch (e, st) {
      _talker?.handle(
        e,
        st,
        "Failed to load/parse flow graph parameters from '$relativeFgPath'",
      );
      // Cache an empty list on failure to prevent repeated load attempts.
      _fgParamCache[canonicalKey] = [];
    }
  }

  /// Retrieves the cached flow graph parameters for a given path.
  /// Returns an empty list if not found or if the path is invalid.
  List<FlowGraphParameter> getCachedFlowGraphParameters(
    String? relativeFgPath,
  ) {
    if (relativeFgPath == null || relativeFgPath.isEmpty) {
      return [];
    }
    // Ensure we use the same path resolution logic to find the correct cache key.
    final canonicalKey = _repo.resolveRelativePath(_tmxPath, relativeFgPath);
    return _fgParamCache[canonicalKey] ?? [];
  }

  /// Clears the parameter cache. This is called when the InspectorDialog is closed.
  void clearFlowGraphParameterCache() {
    _fgParamCache.clear();
  }

  // --- END: PHASE 1 IMPLEMENTATION ---

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

  TexturePackerSpriteData? getSpriteDataForObject(
    TiledObject object,
    TiledMap map,
  ) {
    final frameProp =
        object.properties['initialFrame'] ?? object.properties['initialAnim'];

    if (frameProp is! StringProperty || frameProp.value.isEmpty) {
      return null;
    }

    final spriteName = frameProp.value;
    final atlasProp = object.properties['atlas'];

    if (atlasProp is StringProperty && atlasProp.value.isNotEmpty) {
      final atlasPath = atlasProp.value;
      // Create a unique key for the cache based on the atlas file and sprite name
      final cacheKey = '$atlasPath|$spriteName';

      // 1. Check cache first to avoid re-scanning
      if (_resolvedSpriteCache.containsKey(cacheKey)) {
        return _resolvedSpriteCache[cacheKey];
      }

      // 2. Perform the expensive lookup
      // Note: Debug log removed from here to prevent frame spam
      final result = _findSpriteInAtlases(spriteName, [atlasPath]);
      
      // 3. Store result (even if null) to prevent repeated lookups
      _resolvedSpriteCache[cacheKey] = result;
      return result;
    }

    return null;
  }

  TexturePackerSpriteData? _findSpriteInAtlases(
    String spriteName,
    Iterable<String> tpackerPaths,
  ) {
    for (final path in tpackerPaths) {
      final canonicalKey = _repo.resolveRelativePath(_tmxPath, path);
      final asset = getAsset(canonicalKey);

      if (asset == null) {
        _talker?.warning(
          "[Resolver] Asset not found for key: '$canonicalKey' (Path: $path)",
        );
      } else if (asset is! TexturePackerAssetData) {
        _talker?.warning(
          "[Resolver] Asset at '$canonicalKey' is not TexturePackerAssetData. Type: ${asset.runtimeType}",
        );
      }

      if (asset is TexturePackerAssetData) {
        if (asset.frames.containsKey(spriteName)) {
          return asset.frames[spriteName]!;
        }
        if (asset.animations.containsKey(spriteName)) {
          final firstFrameName = asset.animations[spriteName]!.firstOrNull;
          if (firstFrameName != null &&
              asset.frames.containsKey(firstFrameName)) {
            return asset.frames[firstFrameName]!;
          }
        }
        _talker?.warning(
          "[Resolver] Sprite '$spriteName' not found in atlas '$path'. Available frames: ${asset.frames.length}",
        );
      }
    }
    return null;
  }
}

final tiledAssetResolverProvider = Provider.family
    .autoDispose<AsyncValue<TiledAssetResolver>, String>((ref, tabId) {
      final assetMapAsync = ref.watch(assetMapProvider(tabId));
      final repo = ref.watch(projectRepositoryProvider);
      final project = ref.watch(currentProjectProvider);
      final metadata = ref.watch(tabMetadataProvider)[tabId];
      final talker = ref.watch(talkerProvider);

      return assetMapAsync.whenData((assetMap) {
        if (repo == null || project == null || metadata == null) {
          throw Exception("Project context not available");
        }

        final tmxPath = repo.fileHandler.getPathForDisplay(
          metadata.file.uri,
          relativeTo: project.rootUri,
        );
        return TiledAssetResolver(assetMap, repo, tmxPath, talker);
      });
    });
