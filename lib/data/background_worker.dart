// =========================================
// NEW FILE: lib/data/background_worker.dart
// =========================================

import 'dart:async';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'background_tasks.dart';
import 'cache/hive_cache_repository.dart';
import 'dto/app_state_dto.dart';
import 'dto/project_dto.dart';
import 'persistence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A top-level function that is the entry point for the background isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // A simple logger for the background isolate. We can't use the main
    // isolate's Talker instance, so we create a new one.
    final talker = Talker(
      logger: TalkerLogger(
        settings: TalkerLoggerSettings(
          // Customize colors for easy identification in the console
          colors: {
            TalkerLogType.info: AnsiPen()..cyan(),
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

      final prefs = await SharedPreferences.getInstance();
      final appStateRepo = AppStateRepository(prefs);

      // --- Main Task Router ---
      switch (taskName) {
        case BackgroundTask.saveFullState:
          if (inputData == null) {
            talker.error('Task "$taskName" received null input data.');
            return false;
          }

          // 1. Deserialize all DTOs from the input data.
          final appStateDto = AppStateDto.fromJson(inputData['appStateDto']);
          
          final hotStatesData = inputData['hotStates'] as Map<String, dynamic>? ?? {};
          // Here we would deserialize hot state DTOs, but since they are already maps,
          // we can use them directly for now.
          
          final projectId = appStateDto.lastOpenedProjectId;

          // 2. Perform the I/O operations.
          if (projectId != null) {
            // Cache each dirty tab's state.
            for (final entry in hotStatesData.entries) {
              final tabId = entry.key;
              final stateMap = entry.value as Map<String, dynamic>;
              await cacheRepo.put(projectId, tabId, stateMap);
            }
          }
          
          // Save the global app state.
          await appStateRepo.saveAppStateDto(appStateDto);

          talker.info('Background task "$taskName" completed successfully.');
          return true; // Indicate success.
      }
      
      talker.warning('No handler for task: $taskName');
      return Future.value(true); // Default to success if task is unknown.
    } catch (err, st) {
      talker.handle(err, st, 'Error executing background task: $taskName');
      // In a production app, you might want to report this to a crash logging service.
      return Future.value(false); // Indicate failure.
    }
  });
}