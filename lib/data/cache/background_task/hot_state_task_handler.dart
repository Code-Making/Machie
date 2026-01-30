import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../repositories/cache/hive_cache_repository.dart';

import 'package:talker/talker.dart';

// The service's private, in-memory copy of unsaved data.
// Key: Project ID, Value: Map<Tab ID, Serialized DTO Payload>
final Map<String, Map<String, dynamic>> _inMemoryHotState = {};

/// The entry point for the background isolate, required by flutter_foreground_task.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(HotStateTaskHandler());
}

/// This class runs in a separate isolate and handles all background operations
/// for the hot state cache, including receiving updates and flushing them to disk.
class HotStateTaskHandler extends TaskHandler {
  // This isolate will have its own instance of the repository.
  // Because it uses `IsolatedHive`, it will safely communicate with the
  // single database isolate managed by the `hive_ce` package.
  late HiveCacheRepository _hiveRepo;
  Timer? _shutdownTimer; // <-- ADDED: The inactivity timer
  bool _isShutdownScheduled = false; // <-- ADD THIS FLAG

  /// Called when the foreground service is started.
  /// This is where we initialize resources needed for the background task.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _hiveRepo = HiveCacheRepository(Talker());

    await _hiveRepo.init();
  }

  /// Called whenever the main app sends data to the service using
  /// `FlutterForegroundTask.sendDataToTask`. This is our main communication channel.
  @override
  void onReceiveData(Object data) {
    if (data is! Map<String, dynamic>) {
      return;
    }

    final command = data['command'] as String?;
    switch (command) {
      case 'heartbeat':
        if (!_isShutdownScheduled) {
          _shutdownTimer?.cancel();
        }
        break;

      case 'ui_resumed':
        _isShutdownScheduled = false;
        _shutdownTimer?.cancel();
        break;

      case 'ui_paused':
        _shutdownTimer?.cancel();
        _isShutdownScheduled = true;
        _shutdownTimer = Timer(const Duration(minutes: 5), () {
          FlutterForegroundTask.stopService();
        });
        break;

      case 'clear_tab_state':
        final String? projectId = data['projectId'];
        final String? tabId = data['tabId'];
        if (projectId != null && tabId != null) {
          _inMemoryHotState[projectId]?.remove(tabId);
        }
        break;

      case 'update_hot_state':
        final String? projectId = data['projectId'];
        final String? tabId = data['tabId'];
        final Map<String, dynamic>? payload = data['payload'];
        if (projectId != null && tabId != null && payload != null) {
          (_inMemoryHotState[projectId] ??= {})[tabId] = payload;
        }
        break;

      case 'flush_hot_state':
        _flushInMemoryState();
        break;

      case 'clear_project':
        final String? projectId = data['projectId'];
        if (projectId != null) {
          _inMemoryHotState.remove(projectId);
        }
        break;
    }
  }

  /// Asynchronously writes all data from the in-memory cache to the
  /// persistent Hive database on disk.
  Future<void> _flushInMemoryState() async {
    if (_inMemoryHotState.isEmpty) {
      return;
    }

    final stateToFlush = Map<String, Map<String, dynamic>>.from(
      _inMemoryHotState,
    );
    _inMemoryHotState.clear();

    for (final projectEntry in stateToFlush.entries) {
      final projectId = projectEntry.key;
      for (final tabEntry in projectEntry.value.entries) {
        final tabId = tabEntry.key;
        final payload = tabEntry.value;
        try {
          await _hiveRepo.put<Map<String, dynamic>>(projectId, tabId, payload);
        } catch (e) {
          (_inMemoryHotState[projectId] ??= {})[tabId] = payload;
        }
      }
    }

  }

  /// Called when the service is being destroyed. This serves as a final
  /// opportunity to save any pending data.
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _flushInMemoryState();
    await _hiveRepo.close();
    _shutdownTimer?.cancel();
  }

  // --- Unused callbacks for this implementation ---

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Not used because our `eventAction` is a long repeat interval.
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'STOP_SERVICE_ACTION') {
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
