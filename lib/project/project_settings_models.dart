import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';

import '../data/dto/project_dto.dart';
import '../editor/plugins/editor_plugin_registry.dart';
import '../explorer/explorer_plugin_models.dart';
import '../settings/settings_models.dart';

/// The base abstract class for project-type-specific settings.
/// Project types can extend this to define their own unique settings.
abstract class ProjectSettings extends MachineSettings {}

/// The main container for all project-level settings, both overrides
/// and project-type-specific settings.
@immutable
class ProjectSettingsState {
  /// Stores overrides for app-level editor plugin settings.
  final Map<Type, MachineSettings> pluginSettingsOverrides;

  /// Stores overrides for app-level explorer plugin settings.
  final Map<String, ExplorerPluginSettings> explorerPluginSettingsOverrides;

  /// Stores settings that are unique to the project's type.
  final ProjectSettings? typeSpecificSettings;

  const ProjectSettingsState({
    this.pluginSettingsOverrides = const {},
    this.explorerPluginSettingsOverrides = const {},
    this.typeSpecificSettings,
  });

  /// Converts this live state object into a serializable DTO.
  ProjectSettingsDto toDto() {
    return ProjectSettingsDto(
      pluginSettingsOverrides: pluginSettingsOverrides.map(
        (type, settings) => MapEntry(type.toString(), settings.toJson()),
      ),
      explorerPluginSettingsOverrides: explorerPluginSettingsOverrides.map(
        (id, settings) => MapEntry(id, settings.toJson()),
      ),
      typeSpecificSettings: typeSpecificSettings?.toJson(),
    );
  }

  ProjectSettingsState copyWith({
    Map<Type, MachineSettings>? pluginSettingsOverrides,
    Map<String, ExplorerPluginSettings>? explorerPluginSettingsOverrides,
    ProjectSettings? typeSpecificSettings,
    bool clearTypeSpecificSettings = false,
  }) {
    return ProjectSettingsState(
      pluginSettingsOverrides:
          pluginSettingsOverrides ?? this.pluginSettingsOverrides,
      explorerPluginSettingsOverrides:
          explorerPluginSettingsOverrides ??
          this.explorerPluginSettingsOverrides,
      typeSpecificSettings:
          clearTypeSpecificSettings
              ? null
              : typeSpecificSettings ?? this.typeSpecificSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final mapEquals = const DeepCollectionEquality().equals;

    return other is ProjectSettingsState &&
        mapEquals(other.pluginSettingsOverrides, pluginSettingsOverrides) &&
        mapEquals(
          other.explorerPluginSettingsOverrides,
          explorerPluginSettingsOverrides,
        ) &&
        other.typeSpecificSettings == typeSpecificSettings;
  }

  @override
  int get hashCode => Object.hash(
    const DeepCollectionEquality().hash(pluginSettingsOverrides),
    const DeepCollectionEquality().hash(explorerPluginSettingsOverrides),
    typeSpecificSettings,
  );
}
