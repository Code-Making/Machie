// =========================================
// FINAL CORRECTED FILE: lib/data/cache/hot_state_cache_service.dart
// =========================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logs/logs_provider.dart';
import '../dto/tab_hot_state_dto.dart';
import '../repositories/cache/cache_repository.dart';
import '../repositories/cache/hive_cache_repository.dart';
import 'type_adapter_registry.dart';

import 'background_task/background_cache_service.dart'; // <-- Add import

final hotStateCacheServiceProvider = Provider<HotStateCacheService>((ref) {
  return HotStateCacheService(
    ref.watch(cacheRepositoryProvider),
    ref.watch(typeAdapterRegistryProvider),
    ref.watch(talkerProvider),
    ref.watch(backgroundCacheServiceProvider), // <-- New provider
  );
});

final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  final talker = ref.read(talkerProvider);
  return HiveCacheRepository(talker);
});

class HotStateCacheService {
  final CacheRepository _cacheRepository;
  final TypeAdapterRegistry _adapterRegistry;
  final Talker _talker;
  final BackgroundCacheService _backgroundTaskService; // <-- STORE THE MANAGER
  Timer? _debounceTimer;

  HotStateCacheService(
    this._cacheRepository,
    this._adapterRegistry,
    this._talker,
    this._backgroundTaskService, // <-- ADD TO CONSTRUCTOR
  );

  /// Initializes and starts the background caching service.
  /// This should be called once during app startup.
  Future<void> initializeAndStart() async {
    await _backgroundTaskService.initialize();
    await _backgroundTaskService.start();
  }

  /// Sends a keep-alive signal to the background service.
  Future<void> sendHeartbeat() async {
    await _backgroundTaskService.sendHeartbeat();
  }

  /// Notifies the service that the UI is visible and active again.
  Future<void> notifyUiResumed() async {
    await _backgroundTaskService.notifyUiResumed();
  }

  /// Notifies the service that the UI is paused (e.g., app is backgrounded).
  Future<void> notifyUiPaused() async {
    await _backgroundTaskService.notifyUiPaused();
  }

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
      await _backgroundTaskService.updateHotState(projectId, tabId, payload);
    });
  }

  Future<void> flush() async {
    await _backgroundTaskService.flushHotState();
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
    await _backgroundTaskService.clearTabState(projectId, tabId);
  }

  Future<void> clearProjectCache(String projectId) async {
    _talker.info(
      'HotStateCacheService: Clearing all cache for project "$projectId".',
    );
    // Clear from both persistent and in-memory cache
    await _cacheRepository.clearBox(projectId);
    await _backgroundTaskService.clearProjectCache(projectId);
  }
}
