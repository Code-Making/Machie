// lib/data/repositories/persistent_project_repository.dart
import 'dart:convert';
import 'dart:typed_data';
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
      return Project.fromJson(json).copyWith(metadata: metadata);
    } else {
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

  // REFACTOR: Implement all abstract methods by delegating to fileHandler.
  @override
  Future<DocumentFile?> copyDocumentFile(
          DocumentFile source, String destinationParentUri) =>
      fileHandler.copyDocumentFile(source, destinationParentUri);

  @override
  Future<DocumentFile> createDocumentFile(String parentUri, String name,
          {bool isDirectory = false,
          String? initialContent,
          Uint8List? initialBytes,
          bool overwrite = false}) =>
      fileHandler.createDocumentFile(parentUri, name,
          isDirectory: isDirectory,
          initialContent: initialContent,
          initialBytes: initialBytes,
          overwrite: overwrite);

  @override
  Future<void> deleteDocumentFile(DocumentFile file) =>
      fileHandler.deleteDocumentFile(file);

  @override
  Future<DocumentFile?> getFileMetadata(String uri) =>
      fileHandler.getFileMetadata(uri);

  @override
  Future<List<DocumentFile>> listDirectory(String uri,
          {bool includeHidden = false}) =>
      fileHandler.listDirectory(uri, includeHidden: includeHidden);

  @override
  Future<DocumentFile?> moveDocumentFile(
          DocumentFile source, String destinationParentUri) =>
      fileHandler.moveDocumentFile(source, destinationParentUri);

  @override
  Future<String> readFile(String uri) => fileHandler.readFile(uri);

  @override
  Future<Uint8List> readFileAsBytes(String uri) =>
      fileHandler.readFileAsBytes(uri);

  @override
  Future<DocumentFile?> renameDocumentFile(DocumentFile file, String newName) =>
      fileHandler.renameDocumentFile(file, newName);

  @override
  Future<DocumentFile> writeFile(DocumentFile file, String content) =>
      fileHandler.writeFile(file, content);

  @override
  Future<DocumentFile> writeFileAsBytes(DocumentFile file, Uint8List bytes) =>
      fileHandler.writeFileAsBytes(file, bytes);
}