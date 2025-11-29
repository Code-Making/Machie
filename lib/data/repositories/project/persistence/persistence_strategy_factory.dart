import 'package:shared_preferences/shared_preferences.dart'; // NEW

import '../../../file_handler/file_handler.dart';
import '../project_state_persistence_strategy.dart';
import '../local_folder_persistence_strategy.dart';
import '../simple_state_persistence_strategy.dart';
import '../../../../project/project_models.dart';

/// Defines a factory for creating instances of a specific [ProjectStatePersistenceStrategy].
abstract class PersistenceStrategyFactory {
  ProjectStatePersistenceStrategy get strategyInfo;

  /// Creates a new instance of the persistence strategy.
  ProjectStatePersistenceStrategy create({
    required ProjectMetadata metadata, // CHANGED: Pass full metadata
    required FileHandler fileHandler,
    required SharedPreferences prefs,
    Map<String, dynamic>? projectStateJson,
  });
}


// --- Concrete Factory Implementations ---

class LocalFolderPersistenceStrategyFactory implements PersistenceStrategyFactory {
  @override
  ProjectStatePersistenceStrategy get strategyInfo =>
      LocalFolderPersistenceStrategy(UnimplementedFileHandler(), '');

  @override
  ProjectStatePersistenceStrategy create({
    required ProjectMetadata metadata,
    required FileHandler fileHandler,
    required SharedPreferences prefs,
    Map<String, dynamic>? projectStateJson,
  }) {
    return LocalFolderPersistenceStrategy(fileHandler, metadata.rootUri);
  }
}

class SimpleStatePersistenceStrategyFactory implements PersistenceStrategyFactory {
  @override
  ProjectStatePersistenceStrategy get strategyInfo =>
      SimpleStatePersistenceStrategy(null, UnimplementedPrefs(), '');

  @override
  ProjectStatePersistenceStrategy create({
    required ProjectMetadata metadata,
    required FileHandler fileHandler,
    required SharedPreferences prefs,
    Map<String, dynamic>? projectStateJson,
  }) {
    return SimpleStatePersistenceStrategy(
      projectStateJson,
      prefs,
      metadata.id, // Pass the project ID
    );
  }
}

/// A placeholder FileHandler used only to get descriptive info from a strategy.
/// Throws an error if any of its methods are actually called.
class UnimplementedFileHandler implements FileHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'This FileHandler is a placeholder and should not be used for operations.',
    );
  }
}

/// A placeholder SharedPreferences used only to get descriptive info.
class UnimplementedPrefs implements SharedPreferences {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'This SharedPreferences is a placeholder and should not be used for operations.',
    );
  }
}