// FILE: lib/data/cache/background_task/background_cache_service.dart
// (Add this to the existing file from Step 2)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../logs/logs_provider.dart';
import 'android_foreground_cache_service.dart';
import 'isolate_cache_service.dart';
import 'web_concurrent_cache_service.dart';


/// Abstract interface for a background service that handles caching operations
/// to prevent data loss when the app is in the background.
abstract class BackgroundCacheService {
  /// Initializes the service. Must be called once before any other method.
  Future<void> initialize();

  /// Starts the background service.
  Future<void> start();

  /// Stops the background service.
  Future<void> stop();

  /// Sends a keep-alive signal to the background service.
  Future<void> sendHeartbeat();

  /// Notifies the service that the UI is visible and active again.
  Future<void> notifyUiResumed();

  /// Notifies the service that the UI is paused (e.g., app is backgrounded).
  Future<void> notifyUiPaused();

  /// Instructs the service to immediately write all in-memory cache to disk.
  Future<void> flushHotState();

  /// Sends updated content for a specific tab to the in-memory cache.
  Future<void> updateHotState(
    String projectId,
    String tabId,
    Map<String, dynamic> payload,
  );

  /// Instructs the service to clear the in-memory cache for a specific tab.
  Future<void> clearTabState(String projectId, String tabId);

  /// Instructs the service to clear all in-memory cache for a project.
  Future<void> clearProjectCache(String projectId);
}

/// Factory for creating the appropriate [BackgroundCacheService] based on the platform.
class BackgroundCacheServiceFactory {
  static BackgroundCacheService create(Talker talker) {
    if (kIsWeb) {
      return WebConcurrentCacheService();
    }
    if (Platform.isAndroid) {
      return AndroidForegroundCacheService(talker);
    }
    // For iOS, Linux, Windows, macOS, use the Isolate-based service.
    return IsolateCacheService();
  }
}

/// Riverpod provider that exposes the platform-specific background cache service.
final backgroundCacheServiceProvider = Provider<BackgroundCacheService>((ref) {
  final talker = ref.watch(talkerProvider);
  return BackgroundCacheServiceFactory.create(talker);
});