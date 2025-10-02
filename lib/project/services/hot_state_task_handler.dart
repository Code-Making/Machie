// =========================================
// CORRECTED: lib/project/services/hot_state_task_handler.dart
// =========================================
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

final Map<String, Map<String, dynamic>> _inMemoryHotState = {};

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(HotStateTaskHandler());
}

class HotStateTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // In Installment 3, we will initialize Hive here.
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

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('[Background Service] Service is being destroyed.');
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