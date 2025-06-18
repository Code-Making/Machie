// lib/explorer/explorer_plugin_models.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../project/project_models.dart';

/// Defines the contract for any "explorer" that can be shown in the main drawer.
/// Examples: File Tree, Git Status, Global Search.
abstract class ExplorerPlugin {
  /// The unique identifier for the plugin.
  String get id;

  /// The user-facing name of the explorer.
  String get name;

  /// The icon to display in the explorer selection dropdown.
  IconData get icon;

  /// Builds the primary widget for this explorer.
  /// It is given the [project] to display its relevant data.
  Widget build(WidgetRef ref, Project project);
}
