// lib/data/repositories/simple_project_repository.dart
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import 'project_repository.dart';

/// REFACTOR: Concrete implementation for "Simple Projects" whose state is not
/// persisted in the project folder itself, but rather as part of the main app state
/// in SharedPreferences.
class SimpleProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final Map<String, dynamic>? _projectStateJson;

  SimpleProjectRepository(this.fileHandler, this._projectStateJson);

  @override
  Future<Project> loadProject(ProjectMetadata metadata) async {
    if (_projectStateJson != null) {
      // If we have state from SharedPreferences, use it.
      return Project.fromJson(_projectStateJson!).copyWith(metadata: metadata);
    } else {
      // Otherwise, it's a new simple project.
      return Project.fresh(metadata);
    }
  }

  @override
  Future<void> saveProject(Project project) async {
    // No-op. The state of this project is saved when AppState is saved to SharedPreferences.
    // The updated Project model is held in AppState.
    return;
  }
}