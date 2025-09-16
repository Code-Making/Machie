// =========================================
// UPDATED: lib/project/services/cache_service.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';
import '../../data/cache/cache_repository.dart';
import '../../data/cache/hive_cache_repository.dart';
import '../../data/cache/type_adapter_registry.dart'; // ADDED
import '../../data/dto/tab_hot_state_dto.dart'; // ADDED
import '../../logs/logs_provider.dart';

// ... (cacheRepositoryProvider is unchanged) ...
final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  final talker = ref.read(talkerProvider);
  return HiveCacheRepository(talker);
});

// UPDATED: The CacheService provider now injects the TypeAdapterRegistry.
final cacheServiceProvider = Provider<CacheService>((ref) {
  final cacheRepository = ref.watch(cacheRepositoryProvider);
  final adapterRegistry = ref.watch(typeAdapterRegistryProvider); // ADDED
  final talker = ref.read(talkerProvider);
  return CacheService(cacheRepository, adapterRegistry, talker);
});

/// A service that provides a high-level API for caching application state.
class CacheService {
  final CacheRepository _cacheRepository;
  final TypeAdapterRegistry _adapterRegistry; // ADDED
  final Talker _talker;

  // UPDATED: Constructor now accepts the registry.
  CacheService(this._cacheRepository, this._adapterRegistry, this._talker);

  // A constant key to store the DTO type within the saved JSON.
  static const String _typeKey = '__type__';

  /// Caches the "hot state" of a specific editor tab using its DTO.
  Future<void> cacheTabState(String projectId, String tabId, TabHotStateDto dto) async {
    // 1. Determine the DTO type string.
    final type = _getDtoType(dto);
    if (type == null) {
      _talker.error('Could not cache tab "$tabId": DTO type not found in registry.');
      return;
    }

    // 2. Get the corresponding adapter.
    final adapter = _adapterRegistry.getAdapter(type);
    if (adapter == null) {
      _talker.error('Could not cache tab "$tabId": No adapter found for type "$type".');
      return;
    }

    // 3. Convert the DTO to a JSON map.
    final json = adapter.toJson(dto);

    // 4. Inject the type identifier into the JSON map for later deserialization.
    json[_typeKey] = type;

    _talker.info('CacheService: Caching state for tab "$tabId" in project "$projectId".');
    await _cacheRepository.put<Map<String, dynamic>>(projectId, tabId, json);
  }

  /// Retrieves and deserializes the cached "hot state" for a specific editor tab.
  Future<TabHotStateDto?> getTabState(String projectId, String tabId) async {
    _talker.info('CacheService: Getting state for tab "$tabId" in project "$projectId".');
    
    // 1. Get the raw JSON map from the repository.
    final json = await _cacheRepository.get<Map<String, dynamic>>(projectId, tabId);
    if (json == null) return null;

    // 2. Extract the type identifier.
    final type = json[_typeKey] as String?;
    if (type == null) {
      _talker.error('Could not deserialize tab "$tabId": JSON is missing type key.');
      return null;
    }

    // 3. Look up the correct adapter.
    final adapter = _adapterRegistry.getAdapter(type);
    if (adapter == null) {
      _talker.error('Could not deserialize tab "$tabId": No adapter found for type "$type".');
      return null;
    }

    // 4. Use the adapter to convert the JSON map back into a strongly-typed DTO.
    return adapter.fromJson(json);
  }

  /// Helper to find the DTO type string for a given DTO instance.
  String? _getDtoType(TabHotStateDto dto) {
    return _adapterRegistry.getAdapterTypeForDto(dto);
  }

  // ... (clearTabState and clearProjectCache are unchanged) ...
  Future<void> clearTabState(String projectId, String tabId) async {
    _talker.info('CacheService: Clearing state for tab "$tabId" in project "$projectId".');
    await _cacheRepository.delete(projectId, tabId);
  }

  Future<void> clearProjectCache(String projectId) async {
    _talker.info('CacheService: Clearing all cache for project "$projectId".');
    await _cacheRepository.clearBox(projectId);
  }
}