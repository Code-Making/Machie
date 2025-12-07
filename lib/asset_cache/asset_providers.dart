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
  
  /// Store subscriptions to asset providers for proper lifecycle management
  final List<ProviderSubscription> _assetSubscriptions = [];

  @override
  AsyncValue<Map<String, AssetData>> build(String consumerId) {
    // Clear any existing subscriptions when rebuilding
    _cleanupSubscriptions();
    
    // When the provider is disposed, clean up all subscriptions
    ref.onDispose(() {
      _cleanupSubscriptions();
    });

    // The provider starts in a loading state with no data.
    // The UI is expected to call `updateUris` to trigger the first load.
    return const AsyncValue.data({});
  }

  /// Clean up all existing asset provider subscriptions
  void _cleanupSubscriptions() {
    for (final subscription in _assetSubscriptions) {
      subscription.close();
    }
    _assetSubscriptions.clear();
  }

  /// Update the tracked URIs and set up proper listeners for each asset
  void _updateTrackedUris(Set<String> newUris) {
    // Create listeners for new URIs
    for (final uri in newUris) {
      final assetProvider = assetDataProvider(uri);
      
      // Listen to each asset provider
      final subscription = ref.listen<AsyncValue<AssetData>>(
        assetProvider,
        (previous, next) {
          // When an asset updates, update our map
          if (next is AsyncData<AssetData>) {
            final currentData = state.valueOrNull ?? {};
            final updatedData = Map<String, AssetData>.from(currentData);
            updatedData[uri] = next.value;
            state = AsyncValue.data(updatedData);
          } else if (next is AsyncError<AssetData>) {
            // Handle errors for individual assets
            final currentData = state.valueOrNull ?? {};
            final updatedData = Map<String, AssetData>.from(currentData);
            updatedData[uri] = ErrorAssetData(
              error: next.error,
              stackTrace: next.stackTrace,
            );
            state = AsyncValue.data(updatedData);
          }
        },
      );
      
      _assetSubscriptions.add(subscription);
    }
  }

  /// Imperatively updates the set of asset URIs this provider should manage.
  /// This is the main entry point for the UI.
  Future<Map<String, AssetData>> updateUris(Set<String> newUris) async {
    if (const SetEquality().equals(newUris, _uris)) {
      return state.valueOrNull ?? const {};
    }

    // Update tracked URIs
    _uris = newUris;
    
    // Clean up old subscriptions and create new ones
    _cleanupSubscriptions();
    _updateTrackedUris(newUris);

    return await _fetchAssets();
  }

  /// The core logic for fetching assets and updating the provider's state.
  Future<Map<String, AssetData>> _fetchAssets() async {
    if (_uris.isEmpty) {
      state = const AsyncValue.data({});
      return {};
    }

    state = const AsyncValue<Map<String, AssetData>>.loading().copyWithPrevious(state);

    try {
      final results = <String, AssetData>{};

      // Use watch instead of read to establish proper dependency tracking
      for (final uri in _uris) {
        final assetAsync = ref.watch(assetDataProvider(uri));
        
        if (assetAsync is AsyncData<AssetData>) {
          results[uri] = assetAsync.value;
        } else if (assetAsync is AsyncError<AssetData>) {
          results[uri] = ErrorAssetData(
            error: assetAsync.error,
            stackTrace: assetAsync.stackTrace,
          );
        } else {
          // Still loading - use a placeholder or rethrow
          throw Exception('Asset $uri is still loading');
        }
      }

      state = AsyncValue.data(results);
      return results;
    } catch (e, st) {
      state = AsyncValue<Map<String, AssetData>>.error(e, st).copyWithPrevious(state);
      rethrow;
    }
  }
}