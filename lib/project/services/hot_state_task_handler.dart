// =========================================
// NEW FILE: lib/project/services/hot_state_task_handler.dart
// =========================================
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// The service's private, in-memory copy of unsaved data.
// Key: Project ID, Value: Map<Tab ID, Serialized DTO Payload>
final Map<String, Map<String, dynamic>> _inMemoryHotState = {};

/// The entry point for the background isolate.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(HotStateTaskHandler());
}

class HotStateTaskHandler extends TaskHandler {
  SendPort? _sendPort;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;
    // In Installment 3, we will initialize Hive here.
  }

  @override
  Future<void> onEvent(DateTime timestamp, dynamic data) async {
    if (data is Map<String, dynamic>) {
      final command = data['command'];

      if (command == 'update_hot_state') {
        final String projectId = data['projectId'];
        final String tabId = data['tabId'];
        final Map<String, dynamic> payload = data['payload'];

        // Store the received payload in our in-memory map.
        (_inMemoryHotState[projectId] ??= {})[tabId] = payload;
        print('[Background Service] Updated in-memory hot state for $projectId/$tabId');

      } else if (command == 'flush_hot_state') {
        // This will be implemented in Installment 3.
        print('[Background Service] Received flush command. (Not yet implemented)');
        // For now, just clear the in-memory cache to simulate a flush.
        _inMemoryHotState.clear();

      } else if (command == 'clear_project') {
        final String projectId = data['projectId'];
        _inMemoryHotState.remove(projectId);
        print('[Background Service] Cleared in-memory hot state for project $projectId');
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // This is a last-ditch effort. We'll try to flush here in the final installment.
    print('[Background Service] Service is being destroyed.');
  }

  // --- Unused callbacks for this implementation ---
  @override
  void onButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}
}