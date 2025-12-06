// lib/asset_cache/asset_providers.dart
import 'dart:async';
import 'dart:ui' as ui;

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

/// A secondary provider that efficiently fetches a map of multiple assets at once.
///
/// It watches a set of individual [assetDataProvider] instances and returns a
/// complete map when all of them have successfully loaded. This is the ideal
/// provider for a UI widget to watch, as it aggregates loading states.
final assetMapProvider =
    FutureProvider.autoDispose.family<Map<String, AssetData>, Set<String>>(
  (ref, uris) async {
    if (uris.isEmpty) {
      return {};
    }

    final results = <String, AssetData>{};
    
    // This creates a list of futures. Watching the .future property ensures
    // that we get the result of the AsyncNotifier without causing this
    // provider to rebuild every time the notifier's state changes.
    final futures = uris.map(
      (uri) => ref.watch(assetDataProvider(uri).future)
        .then((data) => results[uri] = data)
    ).toList();

    // Wait for all assets to be fetched and decoded concurrently.
    await Future.wait(futures);

    return results;
  },
);