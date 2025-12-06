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
      
  /// The set of URIs this notifier is currently responsible for.
  Set<String> _uris = {};

  @override
  AsyncValue<Map<String, AssetData>> build(String consumerId) {
    // The provider starts in a loading state with no data.
    // The UI is expected to call `updateUris` to trigger the first load.
    return const AsyncValue.data({});
  }

  /// Imperatively updates the set of asset URIs this provider should manage.
  /// This is the main entry point for the UI.
  Future<void> updateUris(Set<String> newUris) async {
    // If the set of URIs hasn't changed, do nothing.
    if (const SetEquality().equals(newUris, _uris)) {
      return;
    }

    _uris = newUris;
    await _fetchAssets();
  }

  /// The core logic for fetching assets and updating the provider's state.
  Future<void> _fetchAssets() async {
    // If there are no URIs, the state is an empty map.
    if (_uris.isEmpty) {
      state = const AsyncValue.data({});
      return;
    }

    // Immediately enter a loading state, but crucially, preserve the
    // previous data to prevent flickers. This is the key.
    state = AsyncValue.loading().copyWithPrevious(state);

    try {
      final results = <String, AssetData>{};

      // Use Future.wait to fetch all assets concurrently.
      // We use `ref.read` because we are in a method and don't want to
      // create a subscription here; we just want to trigger the load and get the result.
      final futures = _uris.map((uri) async {
        results[uri] = await ref.read(assetDataProvider(uri).future);
      }).toList();

      await Future.wait(futures);

      // Once all assets are loaded, update the state with the final map.
      state = AsyncValue.data(results);
    } catch (e, st) {
      // If any asset fails, the whole operation goes into an error state.
      state = AsyncValue.error(e, st).copyWithPrevious(state);
    }
  }
}