// FILE: lib/data/cache/background_task/web_concurrent_cache_service.dart

import 'background_cache_service.dart';

/// Placeholder implementation for the Web platform.
/// This would likely use Web Workers for background processing.
class WebConcurrentCacheService implements BackgroundCacheService {
  @override
  Future<void> clearProjectCache(String projectId) async {
    throw UnimplementedError();
  }
  
  // ... implement all other methods by throwing UnimplementedError
  // (or as no-ops if preferred) ...

  @override
  Future<void> clearTabState(String projectId, String tabId) {
    throw UnimplementedError();
  }
  
  @override
  Future<void> flushHotState() {
    throw UnimplementedError();
  }
  
  @override
  Future<void> initialize() {
    throw UnimplementedError();
  }
  
  @override
  Future<void> notifyUiPaused() {
    throw UnimplementedError();
  }
  
  @override
  Future<void> notifyUiResumed() {
    throw UnimplementedError();
  }
  
  @override
  Future<void> sendHeartbeat() {
    throw UnimplementedError();
  }
  
  @override
  Future<void> start() {
    throw UnimplementedError();
  }
  
  @override
  Future<void> stop() {
    throw UnimplementedError();
  }
  
  @override
  Future<void> updateHotState(String projectId, String tabId, Map<String, dynamic> payload) {
    throw UnimplementedError();
  }
}