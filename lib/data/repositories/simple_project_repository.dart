// lib/data/repositories/simple_project_repository.dart
import 'dart:typed_data';
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import 'project_repository.dart';

/// REFACTOR: Concrete implementation for "Simple Projects" whose state is not
/// persisted in the project folder itself, but rather as part of the main app state
/// in SharedPreferences.
class SimpleProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final Map<String, dynamic>? _projectStateJson;

  SimpleProjectRepository(this.fileHandler, this._projectStateJson);

  @override
  Future<Project> loadProject(ProjectMetadata metadata) async {
    if (_projectStateJson != null) {
      return Project.fromJson(_projectStateJson!).copyWith(metadata: metadata);
    } else {
      return Project.fresh(metadata);
    }
  }

  @override
  Future<void> saveProject(Project project) async {
    // No-op.
    return;
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