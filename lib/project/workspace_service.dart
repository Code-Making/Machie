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

/// A generic service to manage loading and saving the UI workspace state
/// for a project, including the state of individual plugins.
class WorkspaceService {
  Future<WorkspaceState> _loadFullState(FileHandler fileHandler, String projectDataPath) async {
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
    return const WorkspaceState(activeExplorerPluginId: 'com.machine.file_explorer'); // Default
  }

  Future<void> _saveFullState(
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

  /// Loads the specific state for a single plugin.
  Future<Map<String, dynamic>?> loadPluginState(
    FileHandler fileHandler,
    String projectDataPath,
    String pluginId,
  ) async {
    final fullState = await _loadFullState(fileHandler, projectDataPath);
    return fullState.pluginStates[pluginId];
  }

  /// Saves the state for a single plugin without overwriting others.
  Future<void> savePluginState(
    FileHandler fileHandler,
    String projectDataPath,
    String pluginId,
    Map<String, dynamic> pluginStateJson,
  ) async {
    final fullState = await _loadFullState(fileHandler, projectDataPath);
    final newPluginStates = Map<String, dynamic>.from(fullState.pluginStates);
    newPluginStates[pluginId] = pluginStateJson;
    final newFullState = WorkspaceState(
      activeExplorerPluginId: fullState.activeExplorerPluginId,
      pluginStates: newPluginStates,
    );
    await _saveFullState(fileHandler, projectDataPath, newFullState);
  }

  /// Saves just the active explorer ID.
  Future<void> saveActiveExplorer(
    FileHandler fileHandler,
    String projectDataPath,
    String pluginId,
  ) async {
    final fullState = await _loadFullState(fileHandler, projectDataPath);
    final newFullState = WorkspaceState(
      activeExplorerPluginId: pluginId,
      pluginStates: fullState.pluginStates,
    );
    await _saveFullState(fileHandler, projectDataPath, newFullState);
  }
}