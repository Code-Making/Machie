// lib/project/workspace_service.dart
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/file_handler/file_handler.dart';
import 'workspace_state.dart';

const _workspaceFileName = 'workspace.json';

final workspaceServiceProvider = Provider<WorkspaceService>((ref) {
  return WorkspaceService();
});

/// A service to manage loading and saving the UI-specific workspace state
/// for a project, such as expanded folders and sort orders.
class WorkspaceService {
  /// Loads the workspace state from `.machine/workspace.json`.
  /// If the file doesn't exist, returns a default state.
  Future<WorkspaceState> loadState(FileHandler fileHandler, String projectDataPath) async {
    try {
      final files = await fileHandler.listDirectory(projectDataPath, includeHidden: true);
      final workspaceFile = files.firstWhereOrNull((f) => f.name == _workspaceFileName);

      if (workspaceFile != null) {
        final content = await fileHandler.readFile(workspaceFile.uri);
        return WorkspaceState.fromJson(jsonDecode(content));
      }
    } catch (e) {
      print('Could not load workspace state: $e');
    }
    // Return default state if anything fails
    return const WorkspaceState();
  }

  /// Saves the workspace state to `.machine/workspace.json`.
  Future<void> saveState(
    FileHandler fileHandler,
    String projectDataPath,
    WorkspaceState state,
  ) async {
    try {
      await fileHandler.createDocumentFile(
        projectDataPath,
        _workspaceFileName,
        initialContent: jsonEncode(state.toJson()),
        overwrite: true,
      );
    } catch (e) {
      print('Could not save workspace state: $e');
    }
  }
}