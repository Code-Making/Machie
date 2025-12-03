import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project/project_repository.dart';
import '../../editor/models/asset_models.dart';
import '../../editor/plugins/editor_plugin_registry.dart';
import '../../logs/logs_provider.dart';


import 'live_asset_registry_service.dart'; // <-- ADD THIS IMPORT

/// A provider that serves the "effective" version of an asset.
///
/// It first checks the [LiveAssetRegistryService] to see if an editor has
/// "claimed" the asset for live editing.
/// - If YES, it watches the live [StateNotifier] for real-time updates.
/// - If NO, it falls back to the [ProjectAssetService] to load the static,
///   disk-cached version of the asset.
///
/// All parts of the app should use this provider to ensure they are always
/// viewing the most up-to-date version of an asset.
final effectiveAssetProvider =
    FutureProvider.autoDispose.family<AssetData, DocumentFile>((ref, assetFile) async {
  // 1. Check if there is a "live" version of this asset.
  final liveAssetRegistry = ref.watch(liveAssetRegistryProvider);
  final liveAssetNotifier = liveAssetRegistry.get(assetFile);

  if (liveAssetNotifier != null) {
    // If it's live, watch the notifier for real-time updates.
    // We use ref.watch on the notifier itself to rebuild when its state changes.
    return ref.watch(liveAssetNotifier.select((value) => value));
  } else {
    // If not live, fall back to the ProjectAssetService to load from disk.
    // Since this is a FutureProvider, we can directly await the result.
    final assetService = ref.watch(projectAssetServiceProvider);
    return await assetService.load(assetFile);
  }
});

/// A project-scoped provider for the asset service.
///
/// This provider instantiates the [ProjectAssetService] and ensures its lifecycle
/// is tied to the currently open project. When the project is closed, the
/// service is disposed, automatically clearing its cache.
final projectAssetServiceProvider =
    Provider.autoDispose<ProjectAssetService>((ref) {
  final projectRepo = ref.watch(projectRepositoryProvider);
  if (projectRepo == null) {
    throw StateError('Cannot create ProjectAssetService without a project.');
  }

  final service = ProjectAssetService(ref, projectRepo.fileHandler);
  ref.onDispose(() => service.dispose());
  return service;
});

/// A service that manages the loading and in-memory caching of shared, read-only
/// project assets (e.g., images, JSON data files).
///
/// It uses a plugin-driven system of [AssetDataProvider]s to parse different
/// file types and prevents duplicate loading of the same asset within a project session.
/// It also automatically invalidates its cache when it detects file changes.
class ProjectAssetService {
  final Ref _ref;
  final FileHandler _fileHandler;
  StreamSubscription? _fileOperationSubscription;

  /// A map where keys are file extensions (e.g., '.png') and values are a list
  /// of all providers registered for that extension across all plugins.
  late final Map<String, List<AssetDataProvider<AssetData>>>
      _assetProvidersByExtension;

  /// The in-memory cache.
  /// The key is a record containing the asset's URI and the requested Type,
  /// ensuring type-safe caching.
  /// Storing a `Future` is crucial to handle concurrent requests for the same
  /// asset, ensuring the file is read from disk and parsed only once.
  final Map<(String, Type), Future<AssetData>> _cache = {};

  ProjectAssetService(this._ref, this._fileHandler) {
    _initializeProviders();
    _listenForFileChanges();
  }

  /// Consolidates providers and logs conflicts.
  void _initializeProviders() {
    final talker = _ref.read(talkerProvider);
    final allPlugins = _ref.read(activePluginsProvider);
    final providerMap = <String, List<AssetDataProvider<AssetData>>>{};

    for (final plugin in allPlugins) {
      for (final entry in plugin.assetDataProviders.entries) {
        final extension =
            entry.key.startsWith('.') ? entry.key : '.${entry.key}';
        providerMap.putIfAbsent(extension, () => []).add(entry.value);
      }
    }

    providerMap.forEach((extension, providers) {
      if (providers.length > 1) {
        final providerTypes = providers.map((p) => p.runtimeType).join(', ');
        talker.warning(
          'Asset provider conflict: Multiple providers for extension "$extension": [$providerTypes].',
        );
      }
    });
    _assetProvidersByExtension = Map.unmodifiable(providerMap);
  }

  /// Subscribes to file system events to automatically invalidate the cache.
  void _listenForFileChanges() {
    _fileOperationSubscription =
        _ref.read(fileOperationStreamProvider).listen((event) {
      String? uriToInvalidate;
      if (event is FileDeleteEvent) {
        uriToInvalidate = event.deletedFile.uri;
      } else if (event is FileRenameEvent) {
        uriToInvalidate = event.oldFile.uri;
      }
      // Note: A 'FileModifyEvent' would also be handled here if it existed.
      // For now, delete and rename are the most critical for invalidation.

      if (uriToInvalidate != null) {
        _cache.removeWhere((key, value) => key.$1 == uriToInvalidate);
        _ref.read(talkerProvider).info('Invalidated asset cache for: $uriToInvalidate');
      }
    });
  }

  /// Loads, parses, and caches an asset of type [T] from the given [assetFile].
  /// Returns a specific subclass of [AssetData] (e.g., [ImageAssetData]).
  Future<T> load<T extends AssetData>(DocumentFile assetFile) async {
    final cacheKey = (assetFile.uri, T);
    final existingFuture = _cache[cacheKey];

    if (existingFuture != null) {
      return (await existingFuture) as T;
    }

    final completer = Completer<T>();
    _cache[cacheKey] = completer.future;

    _loadAndParseAsset<T>(assetFile).then((result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }).catchError((error) {
      // On failure, remove from cache so the next attempt can retry.
      _cache.remove(cacheKey);
      if (!completer.isCompleted) {
        // We complete with an ErrorAssetData, but the caller expects T,
        // so we must cast. The caller should check `hasError`.
        completer.complete(ErrorAssetData(assetFile: assetFile, error: error) as T);
      }
    });

    return completer.future;
  }

  Future<T> _loadAndParseAsset<T extends AssetData>(
    DocumentFile assetFile,
  ) async {
    final extension = p.extension(assetFile.name).toLowerCase();
    final providers = _assetProvidersByExtension[extension];

    if (providers == null || providers.isEmpty) {
      throw UnsupportedError('No provider for extension "$extension".');
    }

    final provider = providers.whereType<AssetDataProvider<T>>().firstOrNull;

    if (provider == null) {
      final availableTypes = providers.map((p) => p.runtimeType).join(', ');
      throw UnsupportedError(
        'No provider for "$extension" can produce type "$T". Have: [$availableTypes]',
      );
    }

    final bytes = await _fileHandler.readFileAsBytes(assetFile.uri);
    final parsedData = await provider.parse(bytes, assetFile);
    return parsedData;
  }

  /// Clears the cache and cancels subscriptions.
  /// Called automatically when the provider is disposed.
  void dispose() {
    _fileOperationSubscription?.cancel();
    _cache.clear();
  }
}