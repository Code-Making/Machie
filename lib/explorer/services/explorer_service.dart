// lib/explorer/services/explorer_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/project_repository.dart';
import '../../explorer/explorer_workspace_state.dart';
import '../../project/project_models.dart';

// REFACTOR: Provider for the ExplorerService.
final explorerServiceProvider = Provider<ExplorerService>((ref) {
  return ExplorerService(ref);
});

/// REFACTOR: Application layer service to handle explorer state logic.
class ExplorerService {
  final Ref _ref;
  ExplorerService(this._ref);

  ProjectRepository get _repo {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) {
      throw StateError('ProjectRepository is not available.');
    }
    return repo;
  }

  /// Updates a specific part of the explorer's workspace state and persists it.
  Future<Project> updateWorkspace(
    Project project,
    ExplorerWorkspaceState Function(ExplorerWorkspaceState) updater,
  ) async {
    final newWorkspace = updater(project.workspace);
    final newProject = project.copyWith(workspace: newWorkspace);
    await _repo.saveProject(newProject);
    return newProject;
  }
}