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

/// Resolves a single asset request based on the current Asset Map state.
/// This handles logic for converting relative paths (e.g. "../img.png")
/// into canonical project keys (e.g. "assets/img.png").
final resolvedAssetProvider = Provider.family.autoDispose<AssetData?, ResolvedAssetRequest>((ref, request) {
  final assetMapAsync = ref.watch(assetMapProvider(request.tabId));
  final assetMap = assetMapAsync.valueOrNull;
  
  if (assetMap == null) return null;

  String lookupKey;

  if (request.query.mode == AssetPathMode.projectRelative) {
    lookupKey = request.query.path.replaceAll(r'\', '/');
  } else {
    if (request.query.contextPath == null) {
      return null;
    }

    final contextDir = p.dirname(request.query.contextPath!);
    final rawPath = request.query.path;
    
    final combined = p.join(contextDir, rawPath);
    final normalized = p.normalize(combined);
    
    lookupKey = normalized.replaceAll(r'\', '/');
  }

  return assetMap[lookupKey];
});

/// Generates a closure that can resolve assets relative to a specific file [contextPath].
/// This is primarily used to inject asset resolution logic into CustomPainters, 
/// which cannot use [ref.watch] directly during painting.
final assetResolverProvider = Provider.family.autoDispose<AssetResolver, ({String tabId, String contextPath})>((ref, args) {
  final assetMapAsync = ref.watch(assetMapProvider(args.tabId));
  // If assets aren't loaded yet, return null for everything.
  final assetMap = assetMapAsync.valueOrNull ?? {};

  final contextDir = p.dirname(args.contextPath);

  return (String path) {
    if (path.isEmpty) return null;

    // Resolve relative path logic
    final combined = p.join(contextDir, path);
    final normalized = p.normalize(combined);
    final lookupKey = normalized.replaceAll(r'\', '/');

    return assetMap[lookupKey];
  };
});

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

    if (loader is IDependentAssetLoader) {
      
      final dependencyUris = await loader.getDependencies(ref, file, repo);

      final dependencyValues = [
        for (final uri in dependencyUris) ref.watch(assetDataProvider(uri)),
      ];

      final firstError = dependencyValues.firstWhereOrNull((v) => v.hasError);
      if (firstError != null) {
        throw firstError.error!;
      }
      if (dependencyValues.any((v) => !v.hasValue)) {
        return await Completer<AssetData>().future;
      }
      
    }

    try {
      return await loader.load(ref, file, repo);
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Failed to load asset: $projectRelativeUri');
      return ErrorAssetData(error: e, stackTrace: st);
    }
  }
}

final assetMapProvider = NotifierProvider.autoDispose
    .family<AssetMapNotifier, AsyncValue<Map<String, AssetData>>, String>(
  AssetMapNotifier.new,
);

class AssetMapNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<Map<String, AssetData>>, String> {
  
  Set<String> _uris = {};

  final List<ProviderSubscription> _assetSubscriptions = [];
  
  Timer? _keepAliveTimer;

  @override
  AsyncValue<Map<String, AssetData>> build(String consumerId) {
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

    return const AsyncValue.data({});
  }

  void _cleanupSubscriptions() {
    for (final subscription in _assetSubscriptions) {
      subscription.close();
    }
    _assetSubscriptions.clear();
  }

  Future<Map<String, AssetData>> updateUris(Set<String> newUris) async {
    if (const SetEquality().equals(newUris, _uris)) {
      return state.valueOrNull ?? const {};
    }

    _uris = newUris;
    
    _cleanupSubscriptions();

    state = const AsyncValue<Map<String, AssetData>>.loading().copyWithPrevious(state);

    return await _fetchAndSetupListeners();
  }

  Future<Map<String, AssetData>> _fetchAndSetupListeners() async {
    if (_uris.isEmpty) {
      state = const AsyncValue.data({});
      return {};
    }

    try {
      final results = <String, AssetData>{};

      final futures = _uris.map((uri) async {
        try {
          final data = await ref.read(assetDataProvider(uri).future);
          results[uri] = data;
        } catch (e, st) {
          results[uri] = ErrorAssetData(error: e, stackTrace: st);
        }
      }).toList();

      await Future.wait(futures);

      state = AsyncValue.data(results);

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
      state = AsyncValue<Map<String, AssetData>>.error(e, st).copyWithPrevious(state);
      rethrow;
    }
  }

  /// Callback when a single underlying asset changes (e.g. file modified on disk).
  void _onAssetChanged(String uri, AsyncValue<AssetData> nextAssetValue) {
    
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
      final currentMap = state.valueOrNull ?? {};
      
      final newMap = Map<String, AssetData>.from(currentMap);
      newMap[uri] = newData;
      
      state = AsyncValue.data(newMap);
    }
  }
}