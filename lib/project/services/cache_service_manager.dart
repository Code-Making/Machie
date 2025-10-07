// lib/project/services/cache_service_manager.dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../logs/logs_provider.dart';
import 'hot_state_task_handler.dart';

/// A facade that consolidates all client-side interactions with the
/// FlutterForegroundTask package. No other part of the app should
/// import or directly call flutter_foreground_task.
class CacheServiceManager {
  final Talker _talker;
  static const _iconName = 'ic_stat___'; // As defined in AndroidManifest.xml and drawable folders

  CacheServiceManager(this._talker);

  /// Initializes the foreground task plugin. Must be called once before runApp.
  void init() {
    // This communication port is essential for the UI and service to talk.
    FlutterForegroundTask.initCommunicationPort();
    
    // Configure the notification channel and task options.
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'machine_hot_state_service',
        channelName: 'Machine Hot State Service',
        channelDescription: 'This notification keeps the unsaved file cache alive.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        // FIX: The correct property is `notificationIcon` which takes a `NotificationIcon` object.
        notificationIcon: const NotificationIcon(
          name: _iconName,
          type: 'drawable',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // FIX: The `repeat` action requires an interval in milliseconds (int).
        interval: const Duration(minutes: 999).inMilliseconds,
        autoRunOnBoot: false,
        allowWifiLock: true,
      ),
    );
  }
  
  /// Starts the foreground service.
  Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    _talker.info('[CacheServiceManager] Starting foreground service...');
    await FlutterForegroundTask.startService(
      notificationTitle: 'Machine',
      notificationText: 'File cache is active.',
      notificationButtons: [
        const NotificationButton(
          id: 'STOP_SERVICE_ACTION',
          text: 'Stop Cache',
        ),
      ],
      callback: startCallback,
    );
  }

  /// Stops the foreground service.
  Future<void> stop() async {
    _talker.info('[CacheServiceManager] Stopping foreground service...');
    // FIX: Remove the unnecessary `if` condition. Just call the method.
    if (await FlutterForegroundTask.stopService()) {
      _talker.info('[CacheServiceManager] Service stopped successfully.');
    }
  }

  /// A guard function that ensures the service is running before proceeding.
  Future<void> ensureRunning() async {
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    _talker.warning("[CacheServiceManager] Service was not running. Restarting...");
    await start();
  }

  // --- Communication Methods ---
  // FIX: All methods that call `sendDataToTask` are async (to wait for ensureRunning)
  // but they do NOT await the `sendDataToTask` call itself, as it is a void method.

  Future<void> sendHeartbeat() async {
    await ensureRunning();
    FlutterForegroundTask.sendDataToTask({'command': 'heartbeat'});
  }

  Future<void> notifyUiPaused() async {
    await ensureRunning();
    FlutterForegroundTask.sendDataToTask({'command': 'ui_paused'});
  }

  Future<void> flushHotState() async {
    await ensureRunning();
    FlutterForegroundTask.sendDataToTask({'command': 'flush_hot_state'});
    _talker.info("[CacheServiceManager] Sent flush command.");
  }
  
  Future<void> updateHotState(String projectId, String tabId, Map<String, dynamic> payload) async {
    await ensureRunning();
    final message = {
      'command': 'update_hot_state',
      'projectId': projectId,
      'tabId': tabId,
      'payload': payload,
    };
    FlutterForegroundTask.sendDataToTask(message);
    _talker.verbose("[CacheServiceManager] Sent debounced hot state for tab $tabId.");
  }
  
  Future<void> clearProjectCache(String projectId) async {
    await ensureRunning();
    FlutterForegroundTask.sendDataToTask({
      'command': 'clear_project',
      'projectId': projectId,
    });
  }
}

final cacheServiceManagerProvider = Provider<CacheServiceManager>((ref) {
  return CacheServiceManager(ref.watch(talkerProvider));
});