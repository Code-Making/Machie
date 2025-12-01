import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project/project_repository.dart';
import '../../editor/models/asset_models.dart';
import '../../editor/plugins/editor_plugin_registry.dart';
import '../../logs/logs_provider.dart';

/// A project-scoped provider for the asset cache service.
///
/// This provider ensures that the asset cache is tied to the lifecycle of the
/// currently open project. It automatically disposes the service (clearing the
/// cache) when the project is closed.
final projectAssetCacheProvider =
    Provider.autoDispose<ProjectAssetCacheService>((ref) {
  // Depend on the project repository to ensure this provider is re-created
  // when a new project is opened.
  final projectRepo = ref.watch(projectRepositoryProvider);
  if (projectRepo == null) {
    throw StateError('Cannot create ProjectAssetCacheService without a project.');
  }

  final service = ProjectAssetCacheService(ref, projectRepo.fileHandler);
  ref.onDispose(() => service.dispose());
  return service;
});

/// A service that manages the loading and in-memory caching of shared, read-only
/// project assets (e.g., images, JSON data files).
///
/// It uses a plugin-driven system of [AssetDataProvider]s to parse different
/// file types and prevents duplicate loading of the same asset within a project session.
class ProjectAssetCacheService {
  final Ref _ref;
  final FileHandler _fileHandler;

  /// A map where keys are file extensions (e.g., '.png') and values are a list
  /// of all providers registered for that extension across all plugins.
  late final Map<String, List<AssetDataProvider>> _assetProvidersByExtension;

  /// The in-memory cache.
  /// The key is a record containing the asset's URI and the requested Type,
  /// ensuring type-safe caching.
  /// Storing a `Future` is crucial to handle concurrent requests for the same
  /// asset, ensuring the file is read from disk and parsed only once.
  final Map<(String, Type), Future<AssetData<dynamic>>> _cache = {};

  ProjectAssetCacheService(this._ref, this._fileHandler) {
    _initializeProviders();
  }

  /// Consolidates all `AssetDataProvider`s from active plugins into a single map.
  /// Handles and logs conflicts if multiple plugins register for the same extension.
  void _initializeProviders() {
    final talker = _ref.read(talkerProvider);
    final allPlugins = _ref.read(activePluginsProvider);
    final providerMap = <String, List<AssetDataProvider>>{};

    for (final plugin in allPlugins) {
      for (final entry in plugin.assetDataProviders.entries) {
        final extension =
            entry.key.startsWith('.') ? entry.key : '.${entry.key}';
        final provider = entry.value;

        providerMap.putIfAbsent(extension, () => []).add(provider);
      }
    }

    // Log warnings for any extensions with multiple providers.
    providerMap.forEach((extension, providers) {
      if (providers.length > 1) {
        final providerTypes = providers.map((p) => p.runtimeType).join(', ');
        talker.warning(
          'Asset provider conflict: Multiple providers registered for extension "$extension": [$providerTypes]. '
          'Asset loading will depend on the requested type.',
        );
      }
    });

    _assetProvidersByExtension = Map.unmodifiable(providerMap);
  }

  /// Loads and parses an asset of type [T] from the given [assetFile].
  ///
  /// The result is cached in memory for the duration of the project session.
  /// If the asset is already being loaded as the same type, this method will
  /// await the existing operation and return its result.
  Future<AssetData<T>> load<T extends Object>(DocumentFile assetFile) {
    final cacheKey = (assetFile.uri, T);
    final existingFuture = _cache[cacheKey];

    if (existingFuture != null) {
      return existingFuture.then((value) => value as AssetData<T>);
    }

    final completer = Completer<AssetData<T>>();
    _cache[cacheKey] = completer.future;

    _loadAndParseAsset<T>(assetFile).then((result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }).catchError((error, stackTrace) {
      if (!completer.isCompleted) {
        completer.complete(AssetData.error(error, assetFile));
      }
    });

    return completer.future;
  }

  Future<AssetData<T>> _loadAndParseAsset<T extends Object>(
    DocumentFile assetFile,
  ) async {
    final cacheKey = (assetFile.uri, T);
    try {
      final extension = p.extension(assetFile.name).toLowerCase();
      final providers = _assetProvidersByExtension[extension];

      if (providers == null || providers.isEmpty) {
        throw UnsupportedError('No asset data provider found for extension "$extension".');
      }

      // Find a provider that can produce the requested type T.
      final provider = providers.firstWhereOrNull(
        (p) => p is AssetDataProvider<T>,
      );

      if (provider == null) {
        final availableTypes = providers.map((p) => p.runtimeType).join(', ');
        throw UnsupportedError(
          'No provider for extension "$extension" can produce the requested type "$T". '
          'Available providers: [$availableTypes]',
        );
      }

      final bytes = await _fileHandler.readFileAsBytes(assetFile.uri);
      final parsedData = await provider.parse(bytes);

      return AssetData.success(parsedData as T, assetFile);
    } catch (e) {
      // If any step fails, remove the pending future from the cache so that
      // a subsequent request can retry the operation.
      _cache.remove(cacheKey);
      return AssetData.error(e, assetFile);
    }
  }

  /// Clears the asset cache. Called automatically when the provider is disposed.
  void dispose() {
    _cache.clear();
  }
}