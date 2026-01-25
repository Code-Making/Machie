import '../../dto/project_dto.dart';

/// Defines the contract for loading and saving a project's state DTO.
///
/// This abstraction separates the strategy of how a project's session data
/// is persisted from the repository that handles file system operations.
/// Each implementation is self-describing for dynamic UI creation.
abstract class ProjectStatePersistenceStrategy {
  /// A unique, stable string identifier for this persistence strategy.
  String get id;

  /// A user-facing name for display in the UI (e.g., "Persistent Storage").
  String get name;

  /// A user-facing description for the UI.
  String get description;

  /// Loads the project state and returns it as a [ProjectDto].
  Future<ProjectDto> load();

  /// Saves the given [ProjectDto] to the persistence medium.
  Future<void> save(ProjectDto projectDto);

  /// Clears any long-term persisted state associated with this strategy.
  ///
  /// This is called when a project is removed from the list of known projects.
  Future<void> clear();
}
