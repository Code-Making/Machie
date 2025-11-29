import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/hot_state_cache_service.dart';
import '../../data/content_provider/file_content_provider.dart';
import '../../data/dto/project_dto.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project/project_repository.dart';
import '../../editor/plugins/editor_plugin_registry.dart';
import '../../editor/tab_metadata_notifier.dart';
import '../../explorer/explorer_plugin_registry.dart';
import '../project_models.dart';
import '../project_settings_models.dart';
import '../project_type_handler_registry.dart';

final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService(ref);
});

class OpenProjectResult {
  final ProjectDto projectDto;
  final ProjectMetadata metadata;
  final bool isNew;

  OpenProjectResult({
    required this.projectDto,
    required this.metadata,
    required this.isNew,
  });
}

class ProjectPermissionDeniedException implements Exception {
  final ProjectMetadata metadata;
  final String deniedUri;

  ProjectPermissionDeniedException({
    required this.metadata,
    required this.deniedUri,
  });

  @override
  String toString() =>
      'Permission was denied for project "${metadata.name}" at URI: $deniedUri';
}

class ProjectService {
  final Ref _ref;
  ProjectService(this._ref);

  Future<ProjectDto> openProjectDto(
    ProjectMetadata metadata, {
    Map<String, dynamic>? projectStateJson,
  }) async {
    final handlers = _ref.read(projectTypeHandlerRegistryProvider);
    final handler = handlers[metadata.projectTypeId];

    if (handler == null) {
      throw StateError(
        'No ProjectTypeHandler found for project type: "${metadata.projectTypeId}"',
      );
    }

    // --- SOLUTION: Restore the Permission Pre-Check ---
    // Check for permission BEFORE trying to create the repository or load data.
    if (!await handler.hasPersistedPermission(metadata)) {
      // If permission is missing, throw the specific exception that the
      // AppNotifier knows how to handle to trigger the recovery flow.
      throw ProjectPermissionDeniedException(
        metadata: metadata,
        deniedUri: metadata.rootUri,
      );
    }
    // --- END SOLUTION ---

    // This code now only runs if we are sure we have permission.
    final repo = handler.createRepository(
      metadata,
      projectStateJson: projectStateJson,
    );

    _ref.read(projectRepositoryProvider.notifier).state = repo;

    // The try/catch here is now a secondary safety net, but the primary
    // check above will handle most rehydration failures.
    try {
      return await repo.loadProjectDto();
    } on PermissionDeniedException catch (e) {
      throw ProjectPermissionDeniedException(
        metadata: metadata,
        deniedUri: e.uri,
      );
    }
  }

  ProjectSettingsState rehydrateProjectSettings(
    ProjectSettingsDto? dto,
    ProjectMetadata metadata,
  ) {
    if (dto == null) {
      return const ProjectSettingsState();
    }

    // 1. Rehydrate Plugin Setting Overrides
    final editorPlugins = _ref.read(activePluginsProvider);
    final allKnownAppSettings = [
      GeneralSettings(),
      ...editorPlugins.map((p) => p.settings).whereNotNull(),
    ];
    final Map<Type, MachineSettings> pluginOverrides = {};
    for (final entry in dto.pluginSettingsOverrides.entries) {
      final typeString = entry.key;
      final settingsJson = entry.value;
      final settingTemplate = allKnownAppSettings.firstWhereOrNull(
        (s) => s.runtimeType.toString() == typeString,
      );

      if (settingTemplate != null) {
        // *** THE CRITICAL FIX IS HERE ***
        // 1. Clone the template to get a fresh, clean instance.
        final newInstance = settingTemplate.clone();
        // 2. Hydrate the NEW instance, leaving the original template untouched.
        newInstance.fromJson(settingsJson);
        pluginOverrides[newInstance.runtimeType] = newInstance;
      }
    }

    // 2. Rehydrate Explorer Plugin Setting Overrides
    final explorerPlugins = _ref.read(explorerRegistryProvider);
    final Map<String, ExplorerPluginSettings> explorerOverrides = {};
    for (final entry in dto.explorerPluginSettingsOverrides.entries) {
      final pluginId = entry.key;
      final settingsJson = entry.value;
      final plugin = explorerPlugins.firstWhereOrNull((p) => p.id == pluginId);
      if (plugin?.settings != null) {
        // *** APPLY THE SAME FIX HERE ***
        final newInstance = plugin!.settings!.clone() as ExplorerPluginSettings;
        newInstance.fromJson(settingsJson);
        explorerOverrides[pluginId] = newInstance;
      }
    }

    // 3. Rehydrate Project-Type-Specific Settings
    final handlers = _ref.read(projectTypeHandlerRegistryProvider);
    final handler = handlers[metadata.projectTypeId];
    ProjectSettings? typeSpecificSettings;
    if (handler?.projectTypeSettings != null &&
        dto.typeSpecificSettings != null) {
      // *** AND APPLY THE FIX HERE AS WELL ***
      typeSpecificSettings =
          handler!.projectTypeSettings!.clone() as ProjectSettings;
      typeSpecificSettings.fromJson(dto.typeSpecificSettings!);
    }

    return ProjectSettingsState(
      pluginSettingsOverrides: pluginOverrides,
      explorerPluginSettingsOverrides: explorerOverrides,
      typeSpecificSettings: typeSpecificSettings,
    );
  }

  Future<void> saveProject(Project project) async {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) return;

    final liveMetadata = _ref.read(tabMetadataProvider);
    final registry = _ref.read(fileContentProviderRegistryProvider);
    final projectDto = project.toDto(liveMetadata, registry);

    await repo.saveProjectDto(projectDto);
  }

  Future<void> closeProject(Project project) async {
    await saveProject(project);

    for (final tab in project.session.tabs) {
      tab.plugin.deactivateTab(tab, _ref);
      tab.plugin.disposeTab(tab);
      tab.dispose();
    }

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({
        'command': 'clear_project',
        'projectId': project.id,
      });
    }

    await _ref.read(hotStateCacheServiceProvider).clearProjectCache(project.id);
    _ref.read(projectRepositoryProvider.notifier).state = null;
    _ref.read(tabMetadataProvider.notifier).clear();
  }

  Future<bool> recoverPermissionForProject(
    ProjectMetadata metadata,
    BuildContext context,
  ) async {
    final handlers = _ref.read(projectTypeHandlerRegistryProvider);
    final handler = handlers[metadata.projectTypeId];
    if (handler == null) {
      return false;
    }
    // Delegate the entire recovery flow to the specific handler.
    return handler.recoverPermission(metadata, context);
  }
}
