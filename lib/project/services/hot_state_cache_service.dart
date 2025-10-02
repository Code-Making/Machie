// =========================================
// REVISED: lib/project/services/hot_state_cache_service.dart
// =========================================
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../data/cache/cache_repository.dart';
import '../../data/cache/type_adapter_registry.dart';
import '../../data/dto/tab_hot_state_dto.dart';
import '../../logs/logs_provider.dart';

// The provider definition now explicitly wires up the dependencies.
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

  // Constructor with explicit dependencies - clean and clear.
  HotStateCacheService(this._cacheRepository, this._adapterRegistry, this._talker);

  void updateTabState(String projectId, String tabId, TabHotStateDto dto) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 750), () async {
      if (!await FlutterForegroundTask.isRunningService) {
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

      await FlutterForegroundTask.sendDataToTask(message);
      _talker.info("[HotStateCacheService] Sent debounced hot state for tab $tabId.");
    });
  }

  Future<void> flush() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.sendDataToTask({'command': 'flush_hot_state'});
      _talker.info("[HotStateCacheService] Sent flush command.");
    }
  }

  Future<TabHotStateDto?> getTabState(String projectId, String tabId) async {
    _talker.info('--> getTabState: Getting state for tab "$tabId" in project "$projectId".');
    final json = await _cacheRepository.get<Map<String, dynamic>>(projectId, tabId);
    
    if (json == null) return null;
    
    final type = json['__type__'] as String?;
    if (type == null) return null;

    final adapter = _adapterRegistry.getAdapter(type);
    if (adapter == null) return null;

    return adapter.fromJson(json);
  }
}