// =========================================
// FINAL CORRECTED FILE: lib/project/services/hot_state_cache_service.dart
// =========================================
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../data/cache/cache_repository.dart';
import '../../data/cache/hive_cache_repository.dart';
import '../../data/cache/type_adapter_registry.dart';
import '../../data/dto/tab_hot_state_dto.dart';
import '../../logs/logs_provider.dart';

final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  final talker = ref.read(talkerProvider);
  return HiveCacheRepository(talker);
});

final hotStateCacheServiceProvider = Provider<HotStateCacheService>((ref) {
  return HotStateCacheService(
    ref.watch(cacheRepositoryProvider),
    ref.watch(typeAdapterRegistryProvider),
    ref.watch(talkerProvider),
  );
});

class HotStateCacheService {
  final CacheRepository _cacheRepository;
  final TypeAdapterRegistry _adapterRegistry;
  final Talker _talker;
  Timer? _debounceTimer;

  HotStateCacheService(
      this._cacheRepository, this._adapterRegistry, this._talker);

  void updateTabState(String projectId, String tabId, TabHotStateDto dto) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 750), () {
      FlutterForegroundTask.isRunningService.then((isRunning) {
        if (!isRunning) {
          _talker.warning("Cache service not running. Skipping hot state update.");
          return;
        }

        final type = _adapterRegistry.getAdapterTypeForDto(dto);
        if (type == null) return;

        final adapter = _adapterRegistry.getAdapter(type);
        if (adapter == null) return;

        final payload = adapter.toJson(dto);
        payload['__type__'] = type;

        final message = {
          'command': 'update_hot_state',
          'projectId': projectId,
          'tabId': tabId,
          'payload': payload,
        };

        FlutterForegroundTask.sendDataToTask(message);
        _talker.info(
            "[HotStateCacheService] Sent debounced hot state for tab $tabId.");
      });
    });
  }

  // The "soft flush" method, called on `paused`.
  Future<void> flush() async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({'command': 'flush_hot_state'});
      _talker.info("[HotStateCacheService] Sent flush command.");
    }
  }

  // The "hard flush" method, called on `detached`.
  Future<void> flushAndStop() async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({'command': 'flush_and_stop'});
      _talker.info("[HotStateCacheService] Sent flush-and-stop command.");
    }
  }
  
  // A method to cancel a pending shutdown if the app becomes active again.
  Future<void> notifyAppIsActive() async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({'command': 'cancel_shutdown'});
      _talker.info("[HotStateCacheService] Notified service that app is active.");
    }
  }

  Future<TabHotStateDto?> getTabState(String projectId, String tabId) async {
    _talker.info(
        '--> getTabState: Getting state for tab "$tabId" in project "$projectId".');
    final json =
        await _cacheRepository.get<Map<String, dynamic>>(projectId, tabId);

    if (json == null) {
      return null;
    }

    final type = json['__type__'] as String?;
    if (type == null) return null;

    final adapter = _adapterRegistry.getAdapter(type);
    if (adapter == null) return null;

    return adapter.fromJson(json);
  }

  Future<void> clearTabState(String projectId, String tabId) async {
    _talker.info(
      'HotStateCacheService: Clearing state for tab "$tabId" in project "$projectId".',
    );
    await _cacheRepository.delete(projectId, tabId);
  }

  Future<void> clearProjectCache(String projectId) async {
    _talker.info('HotStateCacheService: Clearing all cache for project "$projectId".');
    await _cacheRepository.clearBox(projectId);
  }
}