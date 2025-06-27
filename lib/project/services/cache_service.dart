// =========================================
// UPDATED: lib/project/services/cache_service.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart'; // ADDED
import '../../data/cache/cache_repository.dart';
import '../../data/cache/hive_cache_repository.dart';
import '../../logs/logs_provider.dart'; // ADDED for talkerProvider

// Provider for the cache repository implementation.
// UPDATED: It now reads the talkerProvider and injects it.
final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  final talker = ref.read(talkerProvider);
  return HiveCacheRepository(talker);
});

// Provider for the CacheService itself.
// UPDATED: It now reads the talkerProvider and injects it.
final cacheServiceProvider = Provider<CacheService>((ref) {
  final cacheRepository = ref.watch(cacheRepositoryProvider);
  final talker = ref.read(talkerProvider);
  return CacheService(cacheRepository, talker);
});

/// A service that provides a high-level API for caching application state.
class CacheService {
  final CacheRepository _cacheRepository;
  final Talker _talker; // ADDED

  // UPDATED: Constructor now accepts Talker.
  CacheService(this._cacheRepository, this._talker);

  /// Caches the "hot state" of a specific editor tab.
  Future<void> cacheTabState(String projectId, String tabId, Map<String, dynamic> state) async {
    // ADDED: High-level log to show intent.
    _talker.info('CacheService: Caching state for tab "$tabId" in project "$projectId".');
    await _cacheRepository.put<Map<String, dynamic>>(projectId, tabId, state);
  }

  /// Retrieves the cached "hot state" for a specific editor tab.
  Future<Map<String, dynamic>?> getTabState(String projectId, String tabId) async {
    _talker.info('CacheService: Getting state for tab "$tabId" in project "$projectId".');
    return await _cacheRepository.get<Map<String, dynamic>>(projectId, tabId);
  }

  /// Deletes the cached state for a single editor tab.
  Future<void> clearTabState(String projectId, String tabId) async {
    _talker.info('CacheService: Clearing state for tab "$tabId" in project "$projectId".');
    await _cacheRepository.delete(projectId, tabId);
  }

  /// Clears all cached data associated with a project.
  Future<void> clearProjectCache(String projectId) async {
    _talker.info('CacheService: Clearing all cache for project "$projectId".');
    await _cacheRepository.clearBox(projectId);
  }
}