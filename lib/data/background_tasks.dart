// =========================================
// NEW FILE: lib/data/background_tasks.dart
// =========================================

/// A central place to define the unique names for all background tasks.
/// This prevents typos and ensures consistency between the main app and the
/// background isolate.
class BackgroundTask {
  /// A unique name for a one-off task that saves the entire application state.
  /// This includes caching dirty tabs, saving the project DTO, and saving the app state DTO.
  static const String saveFullState = 'com.machine.saveFullState';

  // We can add more tasks here in the future.
  // static const String saveFile = 'com.machine.saveFile';
  // static const String cleanCache = 'com.machine.cleanCache';
}