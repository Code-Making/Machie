// =========================================
// FINAL CORRECTED FILE: lib/project/services/hot_state_task_handler.dart
// =========================================
import 'dart:async'; // Import for Timer
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:machine/data/cache/hive_cache_repository.dart';
import 'package:talker/talker.dart'; // Use the core, non-Flutter talker for isolates

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

  /// Called when the foreground service is started.
  /// This is where we initialize resources needed for the background task.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Instantiate the repository. It's safe to use a simple Talker instance
    // here as we don't have access to the full Flutter UI logging.
    _hiveRepo = HiveCacheRepository(Talker());
    
    // Initialize the connection to the shared Hive database isolate.
    await _hiveRepo.init();
    print('[Background Service] IsolatedHive Initialized.');
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
      // --- NEW HEARTBEAT/LIFECYCLE COMMANDS ---
      case 'heartbeat':
        // If we receive a heartbeat, it means the UI is active.
        // We must cancel any pending shutdown timer.
        if (_shutdownTimer?.isActive ?? false) {
          print('[Background Service] Heartbeat received. Shutdown cancelled.');
          _shutdownTimer!.cancel();
        }
        break;

      case 'ui_paused':
        // The UI has gone into the background. Start the shutdown timer.
        print('[Background Service] UI is paused. Starting 5-minute shutdown timer.');
        _shutdownTimer?.cancel(); // Cancel any existing timer
        _shutdownTimer = Timer(const Duration(minutes: 5), () {
          print('[Background Service] Inactivity timeout reached. Stopping service.');
          FlutterForegroundTask.stopService();
        });
        break;
      // --- END OF NEW COMMANDS ---

      case 'update_hot_state':
        final String? projectId = data['projectId'];
        final String? tabId = data['tabId'];
        final Map<String, dynamic>? payload = data['payload'];
        if (projectId != null && tabId != null && payload != null) {
          (_inMemoryHotState[projectId] ??= {})[tabId] = payload;
          // print('[Background Service] Updated in-memory hot state for $projectId/$tabId');
        }
        break;

      case 'flush_hot_state':
        _flushInMemoryState();
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

  /// Asynchronously writes all data from the in-memory cache to the
  /// persistent Hive database on disk.
  Future<void> _flushInMemoryState() async {
    print('[Background Service] Flushing in-memory state to disk...');
    if (_inMemoryHotState.isEmpty) {
      print('[Background Service] In-memory state is empty. Nothing to flush.');
      return;
    }
    
    // Create a copy of the in-memory state to prevent modification during iteration.
    final stateToFlush = Map<String, Map<String, dynamic>>.from(_inMemoryHotState);
    _inMemoryHotState.clear();

    for (final projectEntry in stateToFlush.entries) {
      final projectId = projectEntry.key;
      for (final tabEntry in projectEntry.value.entries) {
        final tabId = tabEntry.key;
        final payload = tabEntry.value;
        try {
          // Use the isolate-safe repository to write to disk.
          await _hiveRepo.put<Map<String, dynamic>>(projectId, tabId, payload);
          print('[Background Service] Flushed $projectId/$tabId');
        } catch (e) {
          print('[Background Service] ERROR flushing $projectId/$tabId: $e');
          // If flushing fails, we should consider putting the data back
          // into the in-memory cache for a retry on the next flush.
          (_inMemoryHotState[projectId] ??= {})[tabId] = payload;
        }
      }
    }
    
    print('[Background Service] Flush complete.');
  }

  /// Called when the service is being destroyed. This serves as a final
  /// opportunity to save any pending data.
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('[Background Service] Service is being destroyed. Final flush attempt...');
    await _flushInMemoryState();
    await _hiveRepo.close();
    _shutdownTimer?.cancel(); // Clean up the timer
    print('[Background Service] Service destroyed.');
  }

  // --- Unused callbacks for this implementation ---

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Not used because our `eventAction` is a long repeat interval.
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'STOP_SERVICE_ACTION') {
      print('[Background Service] "Stop" button pressed. Stopping service.');
      // CORRECTED: Directly call stopService.
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}