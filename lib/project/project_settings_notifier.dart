import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_notifier.dart';
import '../explorer/explorer_plugin_registry.dart';
import '../settings/settings_notifier.dart';
import 'project_models.dart';
import 'project_settings_models.dart';

/// Provides the ProjectSettingsState of the currently active project.
/// This is the "source of truth" for what is overridden at the project level.
final projectSettingsProvider =
    StateNotifierProvider<ProjectSettingsNotifier, ProjectSettingsState?>((
      ref,
    ) {
      return ProjectSettingsNotifier(ref);
    });

class ProjectSettingsNotifier extends StateNotifier<ProjectSettingsState?> {
  final Ref _ref;

  ProjectSettingsNotifier(this._ref)
    : super(_ref.watch(currentProjectProvider.select((p) => p?.settings))) {
    // This listener ensures that if the entire project object is swapped out
    // (e.g., by opening a new project), this notifier's state is updated.
    _ref.listen(currentProjectProvider.select((p) => p?.settings), (
      previous,
      next,
    ) {
      if (mounted) {
        state = next;
      }
    });
  }

  Project? get _currentProject => _ref.read(currentProjectProvider);

  /// Updates an app-level setting override for the current project.
  void updateOverride(MachineSettings newSettings) {
    final project = _currentProject;
    if (project == null || state == null) return;

    // *** THE DEFINITIVE FIX ***
    // We clone the incoming setting using its own clone method.
    final clonedSettings = newSettings.clone();

    final Map<Type, MachineSettings> newPluginOverrides = Map.from(
      state!.pluginSettingsOverrides,
    );
    final Map<String, MachineSettings> newExplorerOverrides = Map.from(
      state!.explorerPluginSettingsOverrides,
    );

    if (clonedSettings is ExplorerPluginSettings) {
      final pluginId =
          _ref
              .read(settingsProvider)
              .explorerPluginSettings
              .entries
              .firstWhere(
                (e) => e.value.runtimeType == clonedSettings.runtimeType,
              )
              .key;
      newExplorerOverrides[pluginId] = clonedSettings;
    } else {
      newPluginOverrides[clonedSettings.runtimeType] = clonedSettings;
    }

    _updateProjectState(
      state!.copyWith(
        pluginSettingsOverrides: newPluginOverrides,
        explorerPluginSettingsOverrides:
            newExplorerOverrides.cast<String, ExplorerPluginSettings>(),
      ),
    );
  }

  /// Removes an app-level setting override from the current project.
  void removeOverride(MachineSettings settingToRemove) {
    final project = _currentProject;
    if (project == null || state == null) return;

    final Map<Type, MachineSettings> newPluginOverrides = Map.from(
      state!.pluginSettingsOverrides,
    );
    final Map<String, MachineSettings> newExplorerOverrides = Map.from(
      state!.explorerPluginSettingsOverrides,
    );

    if (settingToRemove is ExplorerPluginSettings) {
      final pluginId =
          _ref
              .read(settingsProvider)
              .explorerPluginSettings
              .entries
              .firstWhere(
                (e) => e.value.runtimeType == settingToRemove.runtimeType,
              )
              .key;
      newExplorerOverrides.remove(pluginId);
    } else {
      newPluginOverrides.remove(settingToRemove.runtimeType);
    }

    _updateProjectState(
      state!.copyWith(
        pluginSettingsOverrides:
            newPluginOverrides, // CORRECTED (no cast needed)
        explorerPluginSettingsOverrides:
            newExplorerOverrides.cast<String, ExplorerPluginSettings>(),
      ),
    );
  }

  /// Updates the project-type-specific settings for the current project.
  void updateProjectTypeSettings(ProjectSettings newSettings) {
    final project = _currentProject;
    if (project == null || state == null) return;

    _updateProjectState(state!.copyWith(typeSpecificSettings: newSettings));
  }

  void _updateProjectState(ProjectSettingsState newSettingsState) {
    final project = _currentProject;
    if (project == null) return;

    final newProject = project.copyWith(settings: newSettingsState);
    _ref.read(appNotifierProvider.notifier).updateCurrentProject(newProject);
    _ref.read(appNotifierProvider.notifier).saveAppState();
  }
}

/// A provider that exposes just the current project object, for cleaner dependencies.
final currentProjectProvider = Provider<Project?>((ref) {
  return ref.watch(appNotifierProvider).value?.currentProject;
});

/// THE MOST IMPORTANT PROVIDER IN THIS STEP.
/// This provider merges the global app settings with any project-level overrides.
/// The rest of the application should watch THIS provider to get the final,
/// effective settings for the current context.
final effectiveSettingsProvider = Provider<AppSettings>((ref) {
  final globalSettings = ref.watch(settingsProvider);
  final projectOverrides = ref.watch(projectSettingsProvider);

  if (projectOverrides == null) {
    // No project is open, so just use global settings.
    return globalSettings;
  }

  // A project is open, so we merge. Start with a copy of global settings.
  final mergedPluginSettings = Map<Type, MachineSettings>.from(
    globalSettings.pluginSettings,
  );
  final mergedExplorerSettings = Map<String, MachineSettings>.from(
    globalSettings.explorerPluginSettings,
  );

  // Apply project-specific overrides for editor plugins.
  projectOverrides.pluginSettingsOverrides.forEach((type, setting) {
    mergedPluginSettings[type] = setting;
  });

  // Apply project-specific overrides for explorer plugins.
  projectOverrides.explorerPluginSettingsOverrides.forEach((id, setting) {
    mergedExplorerSettings[id] = setting;
  });

  return AppSettings(
    pluginSettings: mergedPluginSettings,
    explorerPluginSettings: mergedExplorerSettings,
  );
});
