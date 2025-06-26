// =========================================
// NEW FILE: lib/project/services/cache_service.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/cache/cache_repository.dart';
import '../../data/cache/hive_cache_repository.dart';

// Provider for the cache repository implementation.
// This is where you would swap HiveCacheRepository for another implementation.
final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  // We can add logic here in the future if we need to switch implementations,
  // but for now, we directly instantiate the Hive version.
  return HiveCacheRepository();
});

// Provider for the CacheService itself.
final cacheServiceProvider = Provider<CacheService>((ref) {
  final cacheRepository = ref.watch(cacheRepositoryProvider);
  return CacheService(cacheRepository);
});

/// A service that provides a high-level API for caching application state.
/// It orchestrates calls to the underlying [CacheRepository].
class CacheService {
  final CacheRepository _cacheRepository;

  CacheService(this._cacheRepository);

  /// Caches the "hot state" of a specific editor tab.
  ///
  /// The [projectId] is used as the `boxName` to scope all data for that project.
  /// The [tabId] is used as the `key` for the specific tab's state.
  Future<void> cacheTabState(String projectId, String tabId, Map<String, dynamic> state) async {
    await _cacheRepository.put<Map<String, dynamic>>(projectId, tabId, state);
  }

  /// Retrieves the cached "hot state" for a specific editor tab.
  ///
  /// Returns the state as a map, or null if no cached state is found.
  Future<Map<String, dynamic>?> getTabState(String projectId, String tabId) async {
    final result = await _cacheRepository.get<Map<String, dynamic>>(projectId, tabId);
    return result;
  }

  /// Deletes the cached state for a single editor tab.
  Future<void> clearTabState(String projectId, String tabId) async {
    await _cacheRepository.delete(projectId, tabId);
  }

  /// Clears all cached data associated with a project.
  /// This should be called when a project is closed or deleted.
  Future<void> clearProjectCache(String projectId) async {
    await _cacheRepository.clearBox(projectId);
  }
}