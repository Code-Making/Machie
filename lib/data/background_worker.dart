// =========================================
// UPDATED: lib/data/background_worker.dart
// =========================================

import 'dart:async';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ADDED
import 'background_tasks.dart';
import 'cache/hive_cache_repository.dart';
import 'dto/app_state_dto.dart';
// REMOVED: No longer need ProjectDto here for this installment
// import 'dto/project_dto.dart'; 
import 'persistence_service.dart';

// A top-level function that is the entry point for the background isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // A simple logger for the background isolate. We can't use the main
    // isolate's Talker instance, so we create a new one.
    final talker = Talker(
      logger: TalkerLogger(
        settings: TalkerLoggerSettings(
          // FIXED: Use LogLevel for the keys, not TalkerLogType.
          colors: {
            LogLevel.info: AnsiPen()..cyan(),
            LogLevel.error: AnsiPen()..red(),
            LogLevel.warning: AnsiPen()..yellow(),
          },
        ),
      ),
    );
    talker.info('Background worker started for task: $taskName');

    try {
      // Initialize all necessary headless services.
      // We are NOT in the Flutter UI isolate, so we can't use Riverpod.
      final cacheRepo = HiveCacheRepository(talker);
      await cacheRepo.init();

      // FIXED: Get an instance of SharedPreferences for the background isolate.
      final prefs = await SharedPreferences.getInstance();
      final appStateRepo = AppStateRepository(prefs); // Pass the prefs instance.

      // --- Main Task Router ---
      switch (taskName) {
        case BackgroundTask.saveFullState:
          if (inputData == null) {
            talker.error('Task "$taskName" received null input data.');
            return false;
          }

          // 1. Deserialize all DTOs from the input data.
          // The inputData itself is Map<String, dynamic>, so we need to access the nested map.
          final appStateDto = AppStateDto.fromJson(inputData['appStateDto'] as Map<String, dynamic>);
          
          final hotStatesData = inputData['hotStates'] as Map<String, dynamic>? ?? {};
          
          final projectId = appStateDto.lastOpenedProjectId;

          // 2. Perform the I/O operations.
          if (projectId != null) {
            // Cache each dirty tab's state.
            talker.info('Caching hot states for ${hotStatesData.length} tabs...');
            for (final entry in hotStatesData.entries) {
              final tabId = entry.key;
              final stateMap = entry.value as Map<String, dynamic>;
              await cacheRepo.put(projectId, tabId, stateMap);
            }
          }
          
          // Save the global app state.
          talker.info('Saving AppStateDto...');
          await appStateRepo.saveAppStateDto(appStateDto);

          talker.info('Background task "$taskName" completed successfully.');
          return true; // Indicate success.
      }
      
      talker.warning('No handler for task: $taskName');
      return Future.value(true);
    } catch (err, st) {
      talker.handle(err, st, 'Error executing background task: $taskName');
      return Future.value(false); // Indicate failure.
    }
  });
}