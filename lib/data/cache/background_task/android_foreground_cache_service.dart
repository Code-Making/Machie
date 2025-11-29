// FILE: lib/data/cache/background_task/android_foreground_cache_service.dart

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../logs/logs_provider.dart';
import 'background_cache_service.dart';
import 'hot_state_task_handler.dart';

/// Android-specific implementation of [BackgroundCacheService] that uses
/// a foreground service to keep the cache alive.
class AndroidForegroundCacheService implements BackgroundCacheService {
  final Talker _talker;

  AndroidForegroundCacheService(this._talker);

  @override
  Future<void> initialize() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'machine_hot_state_service',
        channelName: 'Machine Hot State Service',
        channelDescription:
            'This notification keeps the unsaved file cache alive.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(99999999),
        autoRunOnBoot: false,
        allowWifiLock: true,
      ),
    );
  }

  @override
  Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    _talker.info('[BackgroundCacheService] Starting foreground service...');
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

  @override
  Future<void> stop() async {
    _talker.info('[BackgroundCacheService] Stopping foreground service...');
    if (await FlutterForegroundTask.stopService() == ServiceRequestSuccess) {
      _talker.info('[BackgroundCacheService] Service stopped successfully.');
    }
  }

  Future<void> _ensureRunning() async {
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    _talker.warning(
      "[BackgroundCacheService] Service was not running. Restarting...",
    );
    await start();
  }

  @override
  Future<void> sendHeartbeat() async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask({'command': 'heartbeat'});
  }
  
  @override
  Future<void> notifyUiResumed() async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask({'command': 'ui_resumed'});
  }

  @override
  Future<void> notifyUiPaused() async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask({'command': 'ui_paused'});
  }

  @override
  Future<void> flushHotState() async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask({'command': 'flush_hot_state'});
    _talker.info("[BackgroundCacheService] Sent flush command.");
  }

  @override
  Future<void> updateHotState(
    String projectId,
    String tabId,
    Map<String, dynamic> payload,
  ) async {
    await _ensureRunning();
    final message = {
      'command': 'update_hot_state',
      'projectId': projectId,
      'tabId': tabId,
      'payload': payload,
    };
    FlutterForegroundTask.sendDataToTask(message);
    _talker.verbose(
      "[BackgroundCacheService] Sent debounced hot state for tab $tabId.",
    );
  }

  @override
  Future<void> clearTabState(String projectId, String tabId) async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask({
      'command': 'clear_tab_state',
      'projectId': projectId,
      'tabId': tabId,
    });
    _talker.info("[BackgroundCacheService] Sent clear command for tab $tabId.");
  }

  @override
  Future<void> clearProjectCache(String projectId) async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask({
      'command': 'clear_project',
      'projectId': projectId,
    });
  }
}