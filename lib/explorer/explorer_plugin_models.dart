import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content_provider/file_content_provider.dart';
import '../project/project_models.dart';
import '../settings/settings_models.dart';

abstract class ExplorerPluginSettings extends MachineSettings {}

/// Defines the contract for any "explorer" that can be shown in the main drawer.
abstract class ExplorerPlugin {
  String get id;
  String get name;
  IconData get icon;

  // Plugins that are stateless (like Search) can leave this as null.
  ExplorerPluginSettings? get settings;

  Widget buildSettingsUI(
    ExplorerPluginSettings settings,
    void Function(ExplorerPluginSettings) onChanged,
  ) =>
      const SizedBox.shrink();


  /// A list of [FileContentProvider]s that this plugin introduces.
  /// This allows the explorer to define custom [DocumentFile] types and
  /// how their content should be fetched and saved.
  List<FileContentProvider Function(Ref ref)>
  get fileContentProviderFactories => [];

  Widget build(WidgetRef ref, Project project);
}
