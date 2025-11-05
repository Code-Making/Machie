// lib/explorer/explorer_plugin_models.dart

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content_provider/file_content_provider.dart';
import '../project/project_models.dart';

// REFACTOR: Add a base class for plugin-specific settings.
abstract class ExplorerPluginSettings {
  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);
}

/// Defines the contract for any "explorer" that can be shown in the main drawer.
abstract class ExplorerPlugin {
  String get id;
  String get name;
  IconData get icon;

  // REFACTOR: Add an optional settings object.
  // Plugins that are stateless (like Search) can leave this as null.
  ExplorerPluginSettings? get settings;

  /// A list of [FileContentProvider]s that this plugin introduces.
  /// This allows the explorer to define custom [DocumentFile] types and
  /// how their content should be fetched and saved.
  List<FileContentProvider Function(Ref ref)>
  get fileContentProviderFactories => [];

  Widget build(WidgetRef ref, Project project);
}
