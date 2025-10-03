// =========================================
// FINAL CORRECTED FILE: lib/project/services/hot_state_task_handler.dart
// =========================================

import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:machine/data/cache/hive_cache_repository.dart';
import 'package:talker/talker.dart';

final Map<String, Map<String, dynamic>> _inMemoryHotState = {};
bool _isShutdownPending = false; // The state flag is back.

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(HotStateTaskHandler());
}

class HotStateTaskHandler extends TaskHandler {
  late HiveCacheRepository _hiveRepo;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _isShutdownPending = false; // Reset state on every start.
    _hiveRepo = HiveCacheRepository(Talker());
    await _hiveRepo.init();
    print('[Background Service] IsolatedHive Initialized.');
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map<String, dynamic>) return;

    final command = data['command'] as String?;
    switch (command) {
      case 'update_hot_state':
        if (_isShutdownPending) {
          print('[Background Service] Ignoring state update, shutdown is pending.');
          return;
        }
        final String? projectId = data['projectId'];
        final String? tabId = data['tabId'];
        final Map<String, dynamic>? payload = data['payload'];
        if (projectId != null && tabId != null && payload != null) {
          (_inMemoryHotState[projectId] ??= {})[tabId] = payload;
          print('[Background Service] Updated in-memory hot state for $projectId/$tabId');
        }
        break;

      case 'flush_hot_state': // The "soft flush"
        print('[Background Service] Received flush command.');
        _flushInMemoryState();
        break;

      case 'flush_and_stop': // The "hard flush"
        print('[Background Service] Received flush-and-stop command.');
        _flushAndStop();
        break;
      
      case 'cancel_shutdown': // In case the app becomes active again.
        if (_isShutdownPending) {
          print('[Background Service] Shutdown sequence cancelled by main app.');
          _isShutdownPending = false;
        }
        break;

      case 'clear_project':
        final String? projectId = data['projectId'];
        if (projectId != null) {
          _inMemoryHotState.remove(projectId);
          print('[Background Service] Cleared in-memory hot state for project $projectId');
        }
        break;
    }
  }
  
  Future<void> _flushAndStop() async {
    _isShutdownPending = true;
    await _flushInMemoryState();
    if (_isShutdownPending) {
      print('[Background Service] Flush complete. Stopping service now.');
      FlutterForegroundTask.stopService();
    } else {
      print('[Background Service] Flush complete, but shutdown was cancelled.');
    }
  }

  Future<void> _flushInMemoryState() async {
    print('[Background Service] Flushing in-memory state to disk...');
    if (_inMemoryHotState.isEmpty) {
      print('[Background Service] In-memory state is empty. Nothing to flush.');
      return;
    }
    
    final stateToFlush = Map<String, Map<String, dynamic>>.from(_inMemoryHotState);
    _inMemoryHotState.clear();

    for (final projectEntry in stateToFlush.entries) {
      final projectId = projectEntry.key;
      for (final tabEntry in projectEntry.value.entries) {
        final tabId = tabEntry.key;
        final payload = tabEntry.value;
        try {
          await _hiveRepo.put<Map<String, dynamic>>(projectId, tabId, payload);
          print('[Background Service] Flushed $projectId/$tabId');
        } catch (e) {
          print('[Background Service] ERROR flushing $projectId/$tabId: $e');
          (_inMemoryHotState[projectId] ??= {})[tabId] = payload;
        }
      }
    }
    
    print('[Background Service] Flush complete.');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // This is now our "hard flush" or "final flush".
    print('[Background Service] Service is being destroyed. Final flush attempt...');
    await _flushInMemoryState();
    await _hiveRepo.close();
    print('[Background Service] Service destroyed.');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}