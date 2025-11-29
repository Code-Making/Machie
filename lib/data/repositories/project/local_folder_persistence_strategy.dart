import 'dart:convert';

import 'package:collection/collection.dart';

import '../../dto/project_dto.dart';
import '../../file_handler/file_handler.dart';
import 'project_state_persistence_strategy.dart';

/// A persistence strategy that saves the project state to a `project.json`
/// file inside a hidden `.machine` folder within the project's root directory.
class LocalFolderPersistenceStrategy implements ProjectStatePersistenceStrategy {
  static const _projectDataFolderName = '.machine';
  static const _projectFileName = 'project.json';

  final FileHandler _fileHandler;
  final String _projectRootUri;

  LocalFolderPersistenceStrategy(this._fileHandler, this._projectRootUri);

  @override
  String get id => 'local_folder';

  @override
  String get name => 'Persistent Storage';

  @override
  String get description =>
      'Saves session data in a hidden ".machine" folder inside the project directory. This is the recommended option.';


  /// Ensures the `.machine` directory exists and returns its URI.
  Future<String> _getProjectDataPath() async {
    final files = await _fileHandler.listDirectory(
      _projectRootUri,
      includeHidden: true,
    );
    final machineDir = files.firstWhereOrNull(
      (f) => f.name == _projectDataFolderName && f.isDirectory,
    );
    final dir = machineDir ??
        await _fileHandler.createDocumentFile(
          _projectRootUri,
          _projectDataFolderName,
          isDirectory: true,
        );
    return dir.uri;
  }

  @override
  Future<ProjectDto> load() async {
    final projectDataPath = await _getProjectDataPath();
    final files = await _fileHandler.listDirectory(
      projectDataPath,
      includeHidden: true,
    );
    final projectFile = files.firstWhereOrNull(
      (f) => f.name == _projectFileName,
    );

    if (projectFile != null) {
      try {
        final content = await _fileHandler.readFile(projectFile.uri);
        final json = jsonDecode(content);
        return ProjectDto.fromJson(json);
      } catch (e) {
        // If there's an error reading or parsing, return a fresh DTO.
        return _createFreshDto();
      }
    } else {
      return _createFreshDto();
    }
  }

  @override
  Future<void> save(ProjectDto projectDto) async {
    final projectDataPath = await _getProjectDataPath();
    final content = jsonEncode(projectDto.toJson());
    await _fileHandler.createDocumentFile(
      projectDataPath,
      _projectFileName,
      initialContent: content,
      overwrite: true,
    );
  }
  
  /// For a local folder strategy, clearing is a no-op.
  /// We don't want to delete the .machine folder from the user's project
  /// just because they removed it from the "recent" list.
  @override
  Future<void> clear() async {
    // No-op by design.
    return;
  }

  ProjectDto _createFreshDto() {
    return const ProjectDto(
      session: TabSessionStateDto(
        tabs: [],
        currentTabIndex: 0,
        tabMetadata: {},
      ),
      workspace: ExplorerWorkspaceStateDto(
        activeExplorerPluginId: 'com.machine.file_explorer',
        pluginStates: {},
      ),
    );
  }
}