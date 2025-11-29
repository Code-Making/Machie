// FILE: lib/data/cache/background_task/isolate_cache_service.dart

import 'background_cache_service.dart';

/// Placeholder implementation for Desktop/iOS platforms.
/// This would use a long-running Isolate for persistence.
class IsolateCacheService implements BackgroundCacheService {
  @override
  Future<void> clearProjectCache(String projectId) async {
    // No-op
  }

  @override
  Future<void> clearTabState(String projectId, String tabId) async {
    // No-op
  }

  @override
  Future<void> flushHotState() async {
    // No-op
  }

  @override
  Future<void> initialize() async {
    // No-op
  }

  @override
  Future<void> notifyUiPaused() async {
    // No-op
  }

  @override
  Future<void> notifyUiResumed() async {
    // No-op
  }

  @override
  Future<void> sendHeartbeat() async {
    // No-op
  }

  @override
  Future<void> start() async {
    // No-op
  }

  @override
  Future<void> stop() async {
    // No-op
  }

  @override
  Future<void> updateHotState(String projectId, String tabId, Map<String, dynamic> payload) async {
    // No-op
  }
}