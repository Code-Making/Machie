// =========================================
// CORRECTED: lib/project/services/hot_state_task_handler.dart
// =========================================
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../data/cache/cache_repository.dart';
final Map<String, Map<String, dynamic>> _inMemoryHotState = {};

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(HotStateTaskHandler());
}

class HotStateTaskHandler extends TaskHandler {
 @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // CORRECTED: The constructor is simpler now.
    _hiveRepo = HiveCacheRepository(Talker());
    await _hiveRepo.init();
    print('[Background Service] IsolatedHive Initialized.');
  }

  // CHANGED: The 'onEvent' method is now 'onReceiveData' and has a new signature.
  // It is now synchronous (void) and takes a single 'Object' parameter.
  @override
  void onReceiveData(Object data) {
    if (data is Map<String, dynamic>) {
      final command = data['command'];

      if (command == 'update_hot_state') {
        final String projectId = data['projectId'];
        final String tabId = data['tabId'];
        final Map<String, dynamic> payload = data['payload'];

        (_inMemoryHotState[projectId] ??= {})[tabId] = payload;
        print('[Background Service] Updated in-memory hot state for $projectId/$tabId');

      } else if (command == 'flush_hot_state') {
        print('[Background Service] Received flush command. (Not yet implemented)');
        _inMemoryHotState.clear();

      } else if (command == 'clear_project') {
        final String projectId = data['projectId'];
        _inMemoryHotState.remove(projectId);
        print('[Background Service] Cleared in-memory hot state for project $projectId');
      }
    }
  }

// NEW async helper for flushing
  Future<void> _flushInMemoryState() async {
    print('[Background Service] Flushing in-memory state to disk...');
    // Create a copy of the keys to safely iterate
    final projectsToFlush = _inMemoryHotState.keys.toList();

    for (final projectId in projectsToFlush) {
      final tabCaches = _inMemoryHotState[projectId]!;
      final tabsToFlush = tabCaches.keys.toList();
      for (final tabId in tabsToFlush) {
        final payload = tabCaches[tabId]!;
        try {
          // Use the isolate-safe repository to write to disk.
          await _hiveRepo.put<Map<String, dynamic>>(projectId, tabId, payload);
          print('[Background Service] Flushed $projectId/$tabId');
        } catch (e) {
          print('[Background Service] ERROR flushing $projectId/$tabId: $e');
        }
      }
    }
    _inMemoryHotState.clear();
    print('[Background Service] Flush complete.');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('[Background Service] Service is being destroyed. Final flush attempt...');
    await _flushInMemoryState(); // Final safety net
  }

  // --- Unused callbacks for this implementation ---
  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}