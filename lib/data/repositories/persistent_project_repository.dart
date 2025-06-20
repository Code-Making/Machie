// lib/data/repositories/persistent_project_repository.dart
import 'dart:convert';
import 'package:collection/collection.dart';
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import 'project_repository.dart';

const _projectFileName = 'project.json';

/// REFACTOR: Concrete implementation for projects that save their state
/// to a `.machine/` directory in the file system.
class PersistentProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final String _projectDataPath;

  PersistentProjectRepository(this.fileHandler, this._projectDataPath);

  @override
  Future<Project> loadProject(ProjectMetadata metadata) async {
    final files = await fileHandler.listDirectory(
      _projectDataPath,
      includeHidden: true,
    );
    final projectFile =
        files.firstWhereOrNull((f) => f.name == _projectFileName);

    if (projectFile != null) {
      final content = await fileHandler.readFile(projectFile.uri);
      final json = jsonDecode(content);
      // The metadata passed in is the most current, so we use it.
      // The JSON from the file provides the session and workspace.
      return Project.fromJson(json).copyWith(metadata: metadata);
    } else {
      // No project file found, so this is a fresh project.
      return Project.fresh(metadata);
    }
  }

  @override
  Future<void> saveProject(Project project) async {
    final content = jsonEncode(project.toJson());
    await fileHandler.createDocumentFile(
      _projectDataPath,
      _projectFileName,
      initialContent: content,
      overwrite: true,
    );
  }
}