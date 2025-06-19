// lib/project/workspace_state.dart
import 'package:flutter/foundation.dart';

@immutable
class ExplorerWorkspaceState {
  /// The ID of the last active explorer plugin for this project.
  final String activeExplorerPluginId;

  /// A generic map to hold the persisted state for each plugin, keyed by plugin ID.
  final Map<String, dynamic> pluginStates;

  const ExplorerWorkspaceState({
    required this.activeExplorerPluginId,
    this.pluginStates = const {},
  });

  factory ExplorerWorkspaceState.fromJson(Map<String, dynamic> json) {
    return ExplorerWorkspaceState(
      activeExplorerPluginId:
          json['activeExplorerPluginId'] ?? 'com.machine.file_explorer',
      pluginStates: Map<String, dynamic>.from(json['pluginStates'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'activeExplorerPluginId': activeExplorerPluginId,
    'pluginStates': pluginStates,
  };
}
