// lib/project/workspace_state.dart
import 'package:flutter/foundation.dart';

@immutable
class WorkspaceState {
  /// The ID of the last active explorer plugin for this project.
  final String activeExplorerPluginId;
  /// A generic map to hold the persisted state for each plugin, keyed by plugin ID.
  final Map<String, dynamic> pluginStates;

  const WorkspaceState({
    required this.activeExplorerPluginId,
    this.pluginStates = const {},
  });

  factory WorkspaceState.fromJson(Map<String, dynamic> json) {
    return WorkspaceState(
      activeExplorerPluginId: json['activeExplorerPluginId'] ?? 'com.machine.file_explorer',
      pluginStates: Map<String, dynamic>.from(json['pluginStates'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'activeExplorerPluginId': activeExplorerPluginId,
        'pluginStates': pluginStates,
      };
}