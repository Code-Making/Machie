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
    ref.onDispose(() => _timer?.cancel());
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
  
  // We keep track of active subscriptions so we can close them when URIs are removed.
  final Map<String, ProviderSubscription<AsyncValue<AssetData>>> _subscriptions = {};
  
  // We keep a local cache of the data to emit instant updates.
  final Map<String, AssetData> _localData = {};

  @override
  AsyncValue<Map<String, AssetData>> build(String consumerId) {
    // Clean up subscriptions when this provider is disposed (e.g. tab closed)
    ref.onDispose(() {
      for (final sub in _subscriptions.values) {
        sub.close();
      }
    });
    return const AsyncValue.data({});
  }

  Future<void> updateUris(Set<String> requiredUris) async {
    final currentUris = _subscriptions.keys.toSet();
    
    // 1. Remove URIs that are no longer needed
    final urisToRemove = currentUris.difference(requiredUris);
    for (final uri in urisToRemove) {
      _subscriptions[uri]?.close();
      _subscriptions.remove(uri);
      _localData.remove(uri);
    }

    // 2. Add new URIs
    final urisToAdd = requiredUris.difference(currentUris);
    for (final uri in urisToAdd) {
      // We use listenManual to explicitly manage the subscription.
      // This ensures the assetDataProvider stays alive as long as we need it.
      final subscription = ref.listen<AsyncValue<AssetData>>(
        assetDataProvider(uri),
        (previous, next) {
          // Whenever an individual asset changes (loaded, error, updated),
          // we update our local cache and emit a new map state.
          next.when(
            data: (data) {
              _localData[uri] = data;
              _emitState();
            },
            error: (err, st) {
              _localData[uri] = ErrorAssetData(error: err, stackTrace: st);
              _emitState();
            },
            loading: () {
              // Optionally handle loading state of individual assets if needed,
              // but usually we just wait for data/error.
            },
          );
        },
        fireImmediately: true, // Important: get current value immediately if available
      );
      _subscriptions[uri] = subscription;
    }

    // 3. Handle the "Loading" state for the batch
    // If we added new URIs, we might not have data for them yet.
    // We check if we have data for ALL required URIs.
    if (urisToAdd.isNotEmpty) {
       // Wait for the futures of the NEW items so `updateUris` can be awaited
       // by the caller (essential for the init sequence).
       final futures = urisToAdd.map((uri) => ref.read(assetDataProvider(uri).future));
       
       // While waiting, we can set state to loading-with-previous if you want,
       // OR we can just wait. Since `listenManual` fires immediately, 
       // `_localData` might already be partially populated if cached.
       try {
         await Future.wait(futures);
       } catch (e) {
         // Individual errors are handled by the listeners above, 
         // so we don't strictly need to catch here, but it's good practice.
       }
    }
    
    // Final emission to ensure state is consistent after the await.
    _emitState();
  }

  void _emitState() {
    // If we are disposing, don't emit.
    if (_subscriptions.isEmpty && _localData.isNotEmpty) return; 

    // Create a new map copy to ensure immutability
    final newState = Map<String, AssetData>.from(_localData);
    state = AsyncValue.data(newState);
  }
}