// lib/data/cache/cache_service_manager.dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logs/logs_provider.dart';
import 'hot_state_task_handler.dart';

/// A facade that consolidates all client-side interactions with the
/// FlutterForegroundTask package. No other part of the app should
/// import or directly call flutter_foreground_task.
class CacheServiceManager {
  final Talker _talker;
  static const _iconName = 'ic_stat___'; // As defined in AndroidManifest.xml

  CacheServiceManager(this._talker);

  /// Initializes the foreground task plugin. Must be called once before runApp.
  static void Init() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'machine_hot_state_service',
        channelName: 'Machine Hot State Service',
        channelDescription:
            'This notification keeps the unsaved file cache alive.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        // The icon is NOT set here. It's set in startService.
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // CORRECTED: There is no `.manual()` action. To create an event-driven
        // task that doesn't run on a timer, we use `.repeat()` with a very
        // large interval. This effectively makes it wait for manual triggers.
        eventAction: ForegroundTaskEventAction.repeat(99999999),
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
      notificationText: 'File cache is running.',
      notificationIcon: const NotificationIcon(
        metaDataName: 'my_service_icon_metadata',
      ),
      notificationButtons: [
        const NotificationButton(
          id: 'STOP_SERVICE_ACTION',
          text: 'Stop Cache Service',
        ),
      ],
      callback: startCallback,
    );
  }

  /// Stops the foreground service.
  Future<void> stop() async {
    _talker.info('[CacheServiceManager] Stopping foreground service...');
    if (await FlutterForegroundTask.stopService() == ServiceRequestSuccess) {
      _talker.info('[CacheServiceManager] Service stopped successfully.');
    }
  }

  /// A guard function that ensures the service is running before proceeding.
  Future<void> ensureRunning() async {
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    _talker.warning(
      "[CacheServiceManager] Service was not running. Restarting...",
    );
    await start();
  }

  // --- Communication Methods ---

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

  Future<void> updateHotState(
    String projectId,
    String tabId,
    Map<String, dynamic> payload,
  ) async {
    await ensureRunning();
    final message = {
      'command': 'update_hot_state',
      'projectId': projectId,
      'tabId': tabId,
      'payload': payload,
    };
    FlutterForegroundTask.sendDataToTask(message);
    _talker.verbose(
      "[CacheServiceManager] Sent debounced hot state for tab $tabId.",
    );
  }

  Future<void> clearTabState(String projectId, String tabId) async {
    await ensureRunning();
    FlutterForegroundTask.sendDataToTask({
      'command': 'clear_tab_state',
      'projectId': projectId,
      'tabId': tabId,
    });
    _talker.info("[CacheServiceManager] Sent clear command for tab $tabId.");
  }
  // ----------------------------

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
