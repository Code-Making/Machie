// FILE: lib/editor/plugins/tiled_editor/tiled_asset_resolver.dart

import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/app/app_notifier.dart';

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