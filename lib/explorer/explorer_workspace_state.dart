// lib/explorer/explorer_workspace_state.dart
import 'package:flutter/foundation.dart';
import '../../data/dto/project_dto.dart'; // ADDED

@immutable
class ExplorerWorkspaceState {
  final String activeExplorerPluginId;
  final Map<String, dynamic> pluginStates;

  const ExplorerWorkspaceState({
    required this.activeExplorerPluginId,
    this.pluginStates = const {},
  });

  ExplorerWorkspaceStateDto toDto() {
    return ExplorerWorkspaceStateDto(
      activeExplorerPluginId: activeExplorerPluginId,
      pluginStates: pluginStates,
    );
  }

  ExplorerWorkspaceState copyWith({
    String? activeExplorerPluginId,
    Map<String, dynamic>? pluginStates,
  }) {
    return ExplorerWorkspaceState(
      activeExplorerPluginId: activeExplorerPluginId ?? this.activeExplorerPluginId,
      pluginStates: pluginStates ?? this.pluginStates,
    );
  }
}