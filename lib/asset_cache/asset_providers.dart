import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';
import '../editor/tab_metadata_notifier.dart';

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

    final file = await repo.fileHandler.resolvePath(
      project.rootUri,
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

// --- NEW PROVIDER ---
/// A provider that derives the set of all required asset URIs for the current map.
///
/// It watches the TiledMapNotifier and recalculates the set of URIs whenever the
/// map's structure changes. Riverpod ensures this only recomputes when necessary
/// and provides a stable Set object if the contents haven't changed.
final requiredAssetUrisProvider = Provider<Set<String>>((ref) {
  // Watch the notifier to re-run when the map changes
  final notifier = ref.watch(tiledMapNotifierProvider);
  if (notifier == null) return const {};

  final map = notifier.map;
  final uris = <String>{};

  // The path resolution logic is moved here from the widget
  final repo = ref.watch(projectRepositoryProvider);
  final project = ref.watch(currentProjectProvider);
  final currentTab = ref.watch(currentProjectProvider.select((p) => p?.session.currentTab));
  
  if (repo == null || project == null || currentTab == null) return const {};

  final tmxFile = ref.watch(tabMetadataProvider)[currentTab.id]?.file;
  if (tmxFile == null) return const {};

  final tmxParentUri = repo.fileHandler.getParentUri(tmxFile.uri);
  final tmxParentDisplayPath = repo.fileHandler.getPathForDisplay(
    tmxParentUri,
    relativeTo: project.rootUri,
  );

  String? resolveToProjectRelativePath(String rawPath, String baseDisplayPath) {
    if (rawPath.isEmpty) return null;
    final combinedPath = p.join(baseDisplayPath, rawPath);
    return p.normalize(combinedPath);
  }

  for (final tileset in map.tilesets) {
    final imageSource = tileset.image?.source;
    if (imageSource != null) {
      var baseDisplayPath = tmxParentDisplayPath;
      if (tileset.source != null) {
        final tsxDisplayPath = resolveToProjectRelativePath(tileset.source!, tmxParentDisplayPath);
        if (tsxDisplayPath != null) {
          baseDisplayPath = p.dirname(tsxDisplayPath);
        }
      }
      final projectRelativePath = resolveToProjectRelativePath(imageSource, baseDisplayPath);
      if (projectRelativePath != null) uris.add(projectRelativePath);
    }
  }

  for (final layer in map.layers) {
    if (layer is ImageLayer) {
      final imageSource = layer.image.source;
      if (imageSource != null) {
        final projectRelativePath = resolveToProjectRelativePath(imageSource, tmxParentDisplayPath);
        if (projectRelativePath != null) uris.add(projectRelativePath);
      }
    }
  }

  return uris;
});


/// A secondary provider that efficiently fetches a map of multiple assets at once.
final assetMapProvider = FutureProvider<Map<String, AssetData>>((ref) async {
  final uris = ref.watch(requiredAssetUrisProvider);

  if (uris.isEmpty) {
    return {};
  }

  final results = <String, AssetData>{};
  
  final futures = uris.map(
    (uri) => ref.watch(assetDataProvider(uri).future)
      .then((data) => results[uri] = data)
  ).toList();

  await Future.wait(futures);

  return results;
});

final tiledMapNotifierProvider = Provider<TiledMapNotifier?>((ref) {
  final tab = ref.watch(currentProjectProvider.select((p) => p?.session.currentTab));
  if (tab is! TiledEditorTab) return null;
  return tab.editorKey.currentState?.notifier;
});