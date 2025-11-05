// =========================================
// FINAL CORRECTED FILE: lib/data/cache/hot_state_cache_service.dart
// =========================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/cache/cache_repository.dart';
import '../../data/cache/hive_cache_repository.dart';
import '../type_adapter_registry.dart';
import '../../dto/tab_hot_state_dto.dart';
import '../../../logs/logs_provider.dart';

import 'cache_service_manager.dart'; // <-- IMPORT NEW MANAGER

final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  final talker = ref.read(talkerProvider);
  return HiveCacheRepository(talker);
});

final hotStateCacheServiceProvider = Provider<HotStateCacheService>((ref) {
  return HotStateCacheService(
    ref.watch(cacheRepositoryProvider),
    ref.watch(typeAdapterRegistryProvider),
    ref.watch(talkerProvider),
    ref.watch(cacheServiceManagerProvider), // <-- INJECT THE MANAGER
  );
});

class HotStateCacheService {
  final CacheRepository _cacheRepository;
  final TypeAdapterRegistry _adapterRegistry;
  final Talker _talker;
  final CacheServiceManager _cacheServiceManager; // <-- STORE THE MANAGER
  Timer? _debounceTimer;

  HotStateCacheService(
    this._cacheRepository,
    this._adapterRegistry,
    this._talker,
    this._cacheServiceManager, // <-- ADD TO CONSTRUCTOR
  );

  void updateTabState(String projectId, String tabId, TabHotStateDto dto) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 750), () async {
      final type = _adapterRegistry.getAdapterTypeForDto(dto);
      if (type == null) return;

      final adapter = _adapterRegistry.getAdapter(type);
      if (adapter == null) return;

      final payload = adapter.toJson(dto);
      payload['__type__'] = type;

      // Use the manager to send the data
      await _cacheServiceManager.updateHotState(projectId, tabId, payload);
    });
  }

  Future<void> flush() async {
    await _cacheServiceManager.flushHotState();
  }

  Future<TabHotStateDto?> getTabState(String projectId, String tabId) async {
    _talker.info(
      '--> getTabState: Getting state for tab "$tabId" in project "$projectId".',
    );
    final json = await _cacheRepository.get<Map<String, dynamic>>(
      projectId,
      tabId,
    );

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

    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
      _talker.verbose('Cancelled pending hot state update for tab "$tabId".');
    }

    await _cacheRepository.delete(projectId, tabId);
    await _cacheServiceManager.clearTabState(projectId, tabId);
  }

  Future<void> clearProjectCache(String projectId) async {
    _talker.info(
      'HotStateCacheService: Clearing all cache for project "$projectId".',
    );
    await _cacheRepository.clearBox(projectId);
  }
}
