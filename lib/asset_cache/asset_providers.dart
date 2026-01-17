// lib/asset_cache/asset_providers.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:machine/project/project_settings_notifier.dart';
import '../data/repositories/project/project_repository.dart';
import 'asset_models.dart';
import 'asset_loader_registry.dart';
import 'package:path/path.dart' as p;

/// Resolves an [AssetQuery] into a loaded [AssetData].
///
/// This provider handles the translation from context-relative paths (used by editors
/// like Tiled or Texture Packer) to the canonical project-relative paths used by the AssetMap.
/// Resolves an [AssetQuery] into a loaded [AssetData].
final resolvedAssetProvider = Provider.family.autoDispose<AssetData?, ResolvedAssetRequest>((ref, request) {
  // Watch the asset map for the specific tab
  final assetMapAsync = ref.watch(assetMapProvider(request.tabId));
  final assetMap = assetMapAsync.valueOrNull;
  
  if (assetMap == null) return null;

  final repo = ref.watch(projectRepositoryProvider);
  // We cannot resolve paths if the repository isn't ready.
  if (repo == null) return null;

  String lookupKey;

  if (request.query.mode == AssetPathMode.projectRelative) {
    // If it's already project relative, use it as is (ensuring separators are consistent)
    lookupKey = request.query.path.replaceAll(r'\', '/');
  } else {
    // Delegate resolution logic to the repository
    lookupKey = repo.resolveRelativePath(
      request.query.contextPath!, // Safe due to assertion in AssetQuery
      request.query.path,
    );
  }

  return assetMap[lookupKey];
});

/// A provider that fetches, decodes, and caches a single asset by its
/// project-relative URI.
///
/// It automatically listens for file system events and invalidates itself if the
/// underlying file is modified or deleted, ensuring the UI stays reactive.
final assetDataProvider =
    AsyncNotifierProvider.autoDispose.family<AssetNotifier, AssetData, String>(
  AssetNotifier.new,
);

class AssetNotifier extends AutoDisposeFamilyAsyncNotifier<AssetData, String> {
  Timer? _timer;

  @override
  Future<AssetData> build(String projectRelativeUri) async {
    // --- Keep-alive logic remains the same ---
    final keepAliveLink = ref.keepAlive();
    ref.onDispose(() {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 5), () {
        keepAliveLink.close();
      });
    });
    ref.onCancel(() {
      _timer = Timer(const Duration(seconds: 5), () {
        keepAliveLink.close();
      });
    });
    ref.onResume(() {
      _timer?.cancel();
    });

    // --- Initial setup remains the same ---
    final repo = ref.watch(projectRepositoryProvider);
    final projectRoot = ref.watch(currentProjectProvider.select((p) => p?.rootUri));

    if (repo == null || projectRoot == null) {
      throw Exception('Cannot load asset without an active project.');
    }

    final file = await repo.fileHandler.resolvePath(projectRoot, projectRelativeUri);

    if (file == null) {
      throw Exception('Asset not found at path: $projectRelativeUri');
    }

    final registry = ref.read(assetLoaderRegistryProvider);
    final loader = registry.getLoader(file);

    if (loader == null) {
      throw Exception('No loader registered for file type: ${file.name}');
    }

    // --- File operation listener remains the same ---
    ref.listen<AsyncValue<FileOperationEvent>>(fileOperationStreamProvider, (_, next) {
      // ... (existing logic for file changes)
      final event = next.asData?.value;
      if (event == null) return;

      final String? eventUri;
      if (event is FileModifyEvent) {
        eventUri = event.modifiedFile.uri;
      } else if (event is FileDeleteEvent) {
        eventUri = event.deletedFile.uri;
      } else if (event is FileRenameEvent) {
        if (event.oldFile.uri == file.uri) {
          ref.invalidateSelf();
        }
        return;
      } else {
        eventUri = null;
      }

      if (eventUri != null && eventUri == file.uri) {
        ref.read(talkerProvider).info('Invalidating asset cache for ${file.name} due to file system event.');
        ref.invalidateSelf();
      }
    });

    // --- NEW: Dependency-aware loading logic ---
    if (loader is IDependentAssetLoader) {
      // This is a composite asset that depends on other assets.
      
      // 1. First, get the list of dependency URIs.
      final dependencyUris = await loader.getDependencies(ref, file, repo);

      // 2. Reactively watch all dependencies.
      final dependencyValues = [
        for (final uri in dependencyUris) ref.watch(assetDataProvider(uri)),
      ];

      // 3. Check the state of dependencies. If any are loading or have errored,
      //    this asset inherits that state.
      final firstError = dependencyValues.firstWhereOrNull((v) => v.hasError);
      if (firstError != null) {
        throw firstError.error!;
      }
      if (dependencyValues.any((v) => !v.hasValue)) {
        // One of the dependencies is still loading. We wait.
        // Riverpod will automatically re-run this build method when it's ready.
        // We return a Loading state that never completes.
        return await Completer<AssetData>().future;
      }
      
      // If we reach here, all dependencies are loaded and available via ref.read().
    }

    // --- Original loading logic ---
    // This part now runs for both simple assets, and for dependent assets
    // *after* their dependencies have been successfully loaded and watched.
    try {
      return await loader.load(ref, file, repo);
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Failed to load asset: $projectRelativeUri');
      return ErrorAssetData(error: e, stackTrace: st);
    }
  }
}

/// A NotifierProvider that manages a map of multiple assets for a specific consumer.
///
/// Its family parameter is a stable identifier for the consumer (e.g., a tab ID),
/// ensuring the provider instance itself persists. The set of assets it manages is
/// updated imperatively by calling the `updateUris` method.
final assetMapProvider = NotifierProvider.autoDispose
    .family<AssetMapNotifier, AsyncValue<Map<String, AssetData>>, String>(
  AssetMapNotifier.new,
);

class AssetMapNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<Map<String, AssetData>>, String> {
  
  /// The set of URIs this notifier is currently responsible for.
  Set<String> _uris = {};

  /// Store subscriptions to asset providers for proper lifecycle management.
  final List<ProviderSubscription> _assetSubscriptions = [];
  
  /// Keep-alive timer to prevent flickering on quick tab switches.
  Timer? _keepAliveTimer;

  @override
  AsyncValue<Map<String, AssetData>> build(String consumerId) {
    // --- Keep-Alive Logic ---
    final link = ref.keepAlive();
    ref.onDispose(() {
      _cleanupSubscriptions();
      _keepAliveTimer?.cancel();
    });
    ref.onCancel(() {
      _keepAliveTimer = Timer(const Duration(seconds: 5), () {
        link.close();
      });
    });
    ref.onResume(() {
      _keepAliveTimer?.cancel();
    });
    // ------------------------

    return const AsyncValue.data({});
  }

  /// Clean up all existing asset provider subscriptions.
  void _cleanupSubscriptions() {
    for (final subscription in _assetSubscriptions) {
      subscription.close();
    }
    _assetSubscriptions.clear();
  }

  /// Imperatively updates the set of asset URIs this provider should manage.
  /// Returns a Future that completes when the initial load of these assets is done.
  Future<Map<String, AssetData>> updateUris(Set<String> newUris) async {
    // Optimization: If the set hasn't changed, do nothing.
    if (const SetEquality().equals(newUris, _uris)) {
      return state.valueOrNull ?? const {};
    }

    _uris = newUris;
    
    // Stop listening to old assets immediately.
    _cleanupSubscriptions();

    // 1. Enter loading state, but keep previous data to prevent UI flicker.
    state = const AsyncValue<Map<String, AssetData>>.loading().copyWithPrevious(state);

    // 2. Perform the initial fetch and setup listeners.
    return await _fetchAndSetupListeners();
  }

  /// Fetches all current URIs and then establishes listeners for future changes.
  Future<Map<String, AssetData>> _fetchAndSetupListeners() async {
    if (_uris.isEmpty) {
      state = const AsyncValue.data({});
      return {};
    }

    try {
      final results = <String, AssetData>{};

      // 3. Fetch all assets concurrently using read(... .future).
      // We do NOT use ref.listen here yet. We want the initial snapshot.
      final futures = _uris.map((uri) async {
        try {
          // We assume assetDataProvider returns AssetData (or throws).
          // ErrorAssetData is a subtype of AssetData, so we check for it manually if needed,
          // or catch actual Exceptions thrown by the provider.
          final data = await ref.read(assetDataProvider(uri).future);
          results[uri] = data;
        } catch (e, st) {
          results[uri] = ErrorAssetData(error: e, stackTrace: st);
        }
      }).toList();

      await Future.wait(futures);

      // 4. Update state with the fully loaded map.
      state = AsyncValue.data(results);

      // 5. Now that we have data, set up listeners for *reactive* updates.
      // If a file changes on disk later, these listeners will fire.
      for (final uri in _uris) {
        final sub = ref.listen<AsyncValue<AssetData>>(
          assetDataProvider(uri),
          (previous, next) {
            _onAssetChanged(uri, next);
          },
        );
        _assetSubscriptions.add(sub);
      }
      return results;
    } catch (e, st) {
      // If the batch fetch fails completely (rare, as we catch individual errors above),
      // set the whole map state to error.
      state = AsyncValue<Map<String, AssetData>>.error(e, st).copyWithPrevious(state);
      rethrow;
    }
  }

  /// Callback when a single underlying asset changes (e.g. file modified on disk).
  void _onAssetChanged(String uri, AsyncValue<AssetData> nextAssetValue) {
    // We only care about data or specific error states. 
    // We generally ignore 'loading' states from individual assets to prevent partial map flickers.
    
    AssetData? newData;
    
    if (nextAssetValue is AsyncData<AssetData>) {
      newData = nextAssetValue.value;
    } else if (nextAssetValue is AsyncError<AssetData>) {
      newData = ErrorAssetData(
        error: nextAssetValue.error, 
        stackTrace: nextAssetValue.stackTrace
      );
    }

    if (newData != null) {
      // Gracefully update the map.
      // We use .valueOrNull because we established the data in _fetchAndSetupListeners.
      final currentMap = state.valueOrNull ?? {};
      
      // Create a shallow copy of the map to ensure immutability
      final newMap = Map<String, AssetData>.from(currentMap);
      newMap[uri] = newData;
      
      state = AsyncValue.data(newMap);
    }
  }
}