// lib/project/workspace_service.dart
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/file_handler/file_handler.dart';
import 'explorer_workspace_state.dart';

const _workspaceFileName = 'workspace.json';

final explorerWorkspaceServiceProvider = Provider<ExplorerWorkspaceService>((ref) {
  return ExplorerWorkspaceService();
});

/// A generic service to manage loading and saving the UI workspace state
/// for a project, including the state of individual plugins.
class ExplorerWorkspaceService {
  Future<ExplorerWorkspaceState> loadFullState(
    FileHandler fileHandler,
    String projectDataPath,
  ) async {
    final files = await fileHandler.listDirectory(
      projectDataPath,
      includeHidden: true,
    );
    final workspaceFile = files.firstWhereOrNull(
      (f) => f.name == _workspaceFileName,
    );

    if (workspaceFile != null) {
      final content = await fileHandler.readFile(workspaceFile.uri);
      return ExplorerWorkspaceState.fromJson(jsonDecode(content));
    }
    // should throw if fail ('Could not load workspace state: $e');
    return const ExplorerWorkspaceState(
      activeExplorerPluginId: 'com.machine.file_explorer',
    ); // Default
  }

  Future<void> _saveFullState(
    FileHandler fileHandler,
    String projectDataPath,
    ExplorerWorkspaceState state,
  ) async {
    await fileHandler.createDocumentFile(
      projectDataPath,
      _workspaceFileName,
      initialContent: jsonEncode(state.toJson()),
      overwrite: true,
    );
    // throw if fail('Could not save workspace state: $e');
  }

  /// Loads the specific state for a single plugin.
  Future<Map<String, dynamic>?> loadPluginState(
    FileHandler fileHandler,
    String projectDataPath,
    String pluginId,
  ) async {
    final fullState = await loadFullState(fileHandler, projectDataPath);
    return fullState.pluginStates[pluginId];
  }

  /// Saves the state for a single plugin without overwriting others.
  Future<void> savePluginState(
    FileHandler fileHandler,
    String projectDataPath,
    String pluginId,
    Map<String, dynamic> pluginStateJson,
  ) async {
    final fullState = await loadFullState(fileHandler, projectDataPath);
    final newPluginStates = Map<String, dynamic>.from(fullState.pluginStates);
    newPluginStates[pluginId] = pluginStateJson;
    final newFullState = ExplorerWorkspaceState(
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
    final fullState = await loadFullState(fileHandler, projectDataPath);
    final newFullState = ExplorerWorkspaceState(
      activeExplorerPluginId: pluginId,
      pluginStates: fullState.pluginStates,
    );
    await _saveFullState(fileHandler, projectDataPath, newFullState);
  }
}
