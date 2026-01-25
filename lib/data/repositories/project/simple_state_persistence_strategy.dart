import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../dto/project_dto.dart';
import 'project_state_persistence_strategy.dart';

/// A persistence strategy for "simple" projects.
///
/// It loads its state from a JSON map provided at initialization (typically
/// from the global app state). The `save` operation is a no-op, as the
/// state is expected to be persisted elsewhere when the entire app state is saved.
class SimpleStatePersistenceStrategy
    implements ProjectStatePersistenceStrategy {
  // A JSON map used ONLY for initial rehydration on app start.
  // For all other loads, we use SharedPreferences.
  final Map<String, dynamic>? _rehydrationJson;
  final SharedPreferences _prefs;
  final String _projectId;

  SimpleStatePersistenceStrategy(
    this._rehydrationJson,
    this._prefs,
    this._projectId,
  );

  // The key for this project's long-term state in SharedPreferences.
  String get _storageKey => 'project_state_$_projectId';

  @override
  String get id => 'simple_state';

  @override
  String get name => 'Simple (Temporary) Storage';

  @override
  String get description =>
      'Does not create any files in your project folder. The session is stored with the app.';

  @override
  Future<ProjectDto> load() async {
    // Prioritize the rehydration JSON if it exists (for hot starts).
    if (_rehydrationJson != null) {
      return ProjectDto.fromJson(_rehydrationJson);
    }

    // Otherwise, load from long-term SharedPreferences storage.
    final jsonString = _prefs.getString(_storageKey);
    if (jsonString != null) {
      try {
        return ProjectDto.fromJson(jsonDecode(jsonString));
      } catch (_) {
        // Fallback if parsing fails.
        return _createFreshDto();
      }
    }

    return _createFreshDto();
  }

  @override
  Future<void> save(ProjectDto projectDto) async {
    // The `save` method is now responsible for long-term persistence.
    final jsonString = jsonEncode(projectDto.toJson());
    await _prefs.setString(_storageKey, jsonString);
  }

  @override
  Future<void> clear() async {
    // Remove the long-term state when the project is removed from the recent list.
    await _prefs.remove(_storageKey);
  }

  ProjectDto _createFreshDto() {
    return const ProjectDto(
      session: TabSessionStateDto(
        tabs: [],
        currentTabIndex: 0,
        tabMetadata: {},
      ),
      workspace: ExplorerWorkspaceStateDto(
        activeExplorerPluginId: 'com.machine.file_explorer',
        pluginStates: {},
      ),
    );
  }
}
