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

    final repo = ref.watch(projectRepositoryProvider);
    final projectRoot = ref.watch(currentProjectProvider.select((p)=>p?.rootUri));

    if (repo == null || projectRoot == null) {
      throw Exception('Cannot load asset without an active project.');
    }

    final file = await repo.fileHandler.resolvePath(
      projectRoot,
      projectRelativeUri,
    );

    if (file == null) {
      throw Exception('Asset not found at path: $projectRelativeUri');
    }

    // CORRECTED: Listen to the provider itself, which emits AsyncValue state.
    ref.listen<AsyncValue<FileOperationEvent>>(fileOperationStreamProvider, (_, next) {
      // CORRECTED: 'next' is an AsyncValue, so we can use .asData.
      final event = next.asData?.value;
      if (event == null) return;

      final String? eventUri;
      if (event is FileModifyEvent) {
        eventUri = event.modifiedFile.uri;
      } else if (event is FileDeleteEvent) {
        eventUri = event.deletedFile.uri;
      } else if (event is FileRenameEvent) {
        if (event.oldFile.uri == file.uri) {
          // If the file we are watching is renamed, it's effectively gone.
          ref.invalidateSelf();
        }
        return; // Don't handle rename events further for this provider
      } else {
        eventUri = null;
      }

      if (eventUri != null && eventUri == file.uri) {
        ref.read(talkerProvider).info(
              'Invalidating asset cache for ${file.name} due to file system event.',
            );
        ref.invalidateSelf();
      }
    });

    try {
      final bytes = await repo.readFileAsBytes(file.uri);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return ImageAssetData(image: frame.image);
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
      return;
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
      return;
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