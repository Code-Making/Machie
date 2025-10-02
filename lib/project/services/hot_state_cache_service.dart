// =========================================
// RENAMED FILE: lib/project/services/hot_state_cache_service.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/cache/cache_repository.dart';
import '../../data/cache/hive_cache_repository.dart';
import '../../data/cache/type_adapter_registry.dart';
import '../../data/dto/tab_hot_state_dto.dart';
import '../../logs/logs_provider.dart';

// The existing Hive repository provider is still needed for reading the cache on startup.
final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  final talker = ref.read(talkerProvider);
  return HiveCacheRepository(talker);
});

// RENAMED: The provider is now more descriptive.
final hotStateCacheServiceProvider = Provider<HotStateCacheService>((ref) {
  final cacheRepository = ref.watch(cacheRepositoryProvider);
  final adapterRegistry = ref.watch(typeAdapterRegistryProvider);
  final talker = ref.read(talkerProvider);
  return HotStateCacheService(cacheRepository, adapterRegistry, talker);
});

/// RENAMED: This service is now explicitly for managing "hot" (unsaved) state.
/// The logic inside remains the same for now. In Installment 2, we will
/// change the `cacheTabState` method to send data to the background service.
class HotStateCacheService {
  final CacheRepository _cacheRepository;
  final TypeAdapterRegistry _adapterRegistry;
  final Talker _talker;

  HotStateCacheService(this._cacheRepository, this._adapterRegistry, this._talker);

  static const String _typeKey = '__type__';

  Future<void> cacheTabState(
    String projectId,
    String tabId,
    TabHotStateDto dto,
  ) async {
    _talker.info(
      '--> cacheTabState: Caching state for tab "$tabId" in project "$projectId". DTO: ${dto.runtimeType}',
    );
    final type = _getDtoType(dto);
    if (type == null) {
      _talker.error(
        '--> cacheTabState: Could not cache tab "$tabId": DTO type not found in registry.',
      );
      return;
    }
    final adapter = _adapterRegistry.getAdapter(type);
    if (adapter == null) {
      _talker.error(
        '--> cacheTabState: Could not cache tab "$tabId": No adapter found for type "$type".',
      );
      return;
    }
    final json = adapter.toJson(dto);
    json[_typeKey] = type;

    try {
      await _cacheRepository.put<Map<String, dynamic>>(projectId, tabId, json);
      _talker.info(
        '--> cacheTabState: Successfully cached state for tab "$tabId".',
      );
    } catch (e, st) {
      _talker.handle(
        e,
        st,
        '--> cacheTabState: Failed to cache state for tab "$tabId".',
      );
    }
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
      _talker.warning(
        '--> getTabState: No cached state found for tab "$tabId".',
      );
      return null;
    }
    final type = json[_typeKey] as String?;
    if (type == null) {
      _talker.error(
        '--> getTabState: Could not deserialize tab "$tabId": JSON is missing type key "$_typeKey".',
      );
      return null;
    }
    final adapter = _adapterRegistry.getAdapter(type);
    if (adapter == null) {
      _talker.error(
        '--> getTabState: Could not deserialize tab "$tabId": No adapter found for type "$type".',
      );
      return null;
    }
    try {
      final dto = adapter.fromJson(json);
      _talker.info(
        '--> getTabState: Successfully deserialized DTO for tab "$tabId". DTO: ${dto.runtimeType}',
      );
      return dto;
    } catch (e, st) {
      _talker.handle(
        e,
        st,
        '--> getTabState: Failed to deserialize DTO for tab "$tabId".',
      );
      return null;
    }
  }

  String? _getDtoType(TabHotStateDto dto) {
    return _adapterRegistry.getAdapterTypeForDto(dto);
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