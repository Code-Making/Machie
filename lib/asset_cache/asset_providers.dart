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
    AsyncNotifierProvider.family<AssetNotifier, AssetData, String>(
  AssetNotifier.new,
);

class AssetNotifier extends FamilyAsyncNotifier<AssetData, String> {
  @override
  Future<AssetData> build(String projectRelativeUri) async {
    final repo = ref.watch(projectRepositoryProvider);
    final project = ref.watch(currentProjectProvider);

    if (repo == null || project == null) {
      throw Exception('Cannot load asset without an active project.');
    }

    // Resolve the relative path to a full file object
    final file = await repo.fileHandler.resolvePath(
      project.rootUri,
      projectRelativeUri,
    );

    if (file == null) {
      throw Exception('Asset not found at path: $projectRelativeUri');
    }

    // Listen for file changes to invalidate this specific provider instance.
    // Riverpod will automatically dispose this listener when the provider is disposed.
    ref.listen<FileOperationEvent>(fileOperationStreamProvider.stream, (_, next) {
      final event = next.asData?.value;
      if (event == null) return;
      
      final String? eventUri;
      if (event is FileModifyEvent) {
        eventUri = event.modifiedFile.uri;
      } else if (event is FileDeleteEvent) {
        eventUri = event.deletedFile.uri;
      } else if (event is FileRenameEvent) {
        if(event.oldFile.uri == file.uri) {
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

    // Fetch and decode the image
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
    FutureProvider.family<Map<String, AssetData>, Set<String>>(
  (ref, uris) async {
    final results = <String, AssetData>{};
    final futures = <Future>[];

    for (final uri in uris) {
      final future = ref.watch(assetDataProvider(uri).future);
      futures.add(
        future.then((data) => results[uri] = data),
      );
    }

    // Wait for all assets to be fetched and decoded concurrently.
    await Future.wait(futures);

    return results;
  },
);