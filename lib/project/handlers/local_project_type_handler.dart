import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/file_handler/local_file_handler.dart';
import '../../data/repositories/project/persistence/persistence_strategy_factory.dart';
import '../../data/repositories/project/persistence/persistence_strategy_registry.dart';
import '../../data/repositories/project/project_repository.dart';
import '../../data/shared_preferences.dart'; // NEW
import '../../platform/platform_file_service.dart';
import '../project_models.dart';
import '../project_settings_models.dart';
import '../project_type_handler.dart';
import 'local_project_settings.dart';
import 'local_project_settings_ui.dart';


class LocalProjectTypeHandler implements ProjectTypeHandler {
  final Ref _ref;

  LocalProjectTypeHandler(this._ref);

  @override
  String get id => 'local';

  @override
  String get name => 'Local Folder Project';

  @override
  String get description =>
      'A project stored directly on your device\'s file system.';

  @override
  IconData get icon => Icons.folder_outlined;

  @override
  List<String> get supportedPersistenceTypeIds => [
        'local_folder',
        'simple_state',
      ];
      
  @override
  ProjectSettings? get projectTypeSettings => LocalProjectSettings();

  @override
  Widget buildProjectTypeSettingsUI(
    ProjectSettings settings,
    void Function(ProjectSettings) onChanged,
  ) {
    return LocalProjectSettingsUI(
      settings: settings as LocalProjectSettings,
      onChanged: onChanged,
    );
  }

      
  @override
  Future<bool> hasPersistedPermission(ProjectMetadata metadata) {
    // For a local project, this simply delegates to the PlatformFileService.
    // For a future SSH handler, this might check for valid stored credentials.
    final platformService = _ref.read(platformFileServiceProvider);
    return platformService.hasPermission(metadata.rootUri);
  }


  @override
  Future<ProjectMetadata?> initiateNewProject(
    BuildContext context,
    String persistenceTypeId,
  ) async {
    // This method is now very focused. It only does what a 'local' handler should do:
    // ask for a local folder.
    final platformService = _ref.read(platformFileServiceProvider);
    final pickedDir = await platformService.pickDirectoryForProject();

    if (pickedDir == null) {
      return null;
    }

    // It then constructs the metadata using the persistenceTypeId passed in from the UI.
    return ProjectMetadata(
      id: const Uuid().v4(),
      name: pickedDir.name,
      rootUri: pickedDir.uri,
      projectTypeId: id,
      persistenceTypeId: persistenceTypeId,
      lastOpenedDateTime: DateTime.now(),
    );
  }

  @override
  ProjectRepository createRepository(
    ProjectMetadata metadata, {
    Map<String, dynamic>? projectStateJson,
  }) {
    final fileHandler = LocalFileHandlerFactory.create(metadata.rootUri);
    final persistenceRegistry = _ref.read(persistenceStrategyRegistryProvider);
    final persistenceFactory = persistenceRegistry[metadata.persistenceTypeId];
    final sharedPrefs = _ref.read(sharedPreferencesProvider).value;

    if (persistenceFactory == null) {
      throw StateError(
        'No PersistenceStrategyFactory found for persistence type: "${metadata.persistenceTypeId}"',
      );
    }
    if (sharedPrefs == null) {
      throw StateError('SharedPreferences not available for repository creation.');
    }

    final persistenceStrategy = persistenceFactory.create(
      metadata: metadata, // Pass full metadata
      fileHandler: fileHandler,
      prefs: sharedPrefs, // Pass the SharedPreferences instance
      projectStateJson: projectStateJson,
    );

    return ProjectRepository(
      rootUri: metadata.rootUri,
      fileHandler: fileHandler,
      persistenceStrategy: persistenceStrategy,
    );
  }

  @override
  Future<bool> recoverPermission(
    ProjectMetadata metadata,
    BuildContext context,
  ) {
    final platformService = _ref.read(platformFileServiceProvider);
    return platformService.reRequestProjectPermission(metadata.rootUri);
  }

  // REMOVED: _showPersistenceTypeDialog helper method.
  // This UI logic will now live in the NewProjectScreen.
}