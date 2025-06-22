// lib/data/repositories/simple_project_repository.dart
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // NEW
import '../../data/file_handler/file_handler.dart';
import '../../logs/logs_provider.dart'; // NEW
import '../../project/project_models.dart';
import 'project_hierarchy_cache.dart'; // NEW
import 'project_repository.dart';

/// REFACTOR: Concrete implementation for "Simple Projects" whose state is not
/// persisted in the project folder itself.
class SimpleProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final Map<String, dynamic>? _projectStateJson;

  @override
  late final ProjectHierarchyCache hierarchyCache;

  SimpleProjectRepository(
      this.fileHandler, this._projectStateJson, Ref ref) {
    hierarchyCache = ProjectHierarchyCache(fileHandler, ref.read(talkerProvider));
  }

  // ... (loadProject and saveProject are unchanged) ...
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

  // --- REFACTORED File Operations ---
  @override
  Future<DocumentFile> createDocumentFile(String parentUri, String name,
      {bool isDirectory = false,
      String? initialContent,
      Uint8List? initialBytes,
      bool overwrite = false}) async {
    final newFile = await fileHandler.createDocumentFile(parentUri, name,
        isDirectory: isDirectory,
        initialContent: initialContent,
        initialBytes: initialBytes,
        overwrite: overwrite);
    hierarchyCache.add(newFile, parentUri);
    return newFile;
  }

  @override
  Future<void> deleteDocumentFile(DocumentFile file) async {
    final parentUri = file.uri.substring(0, file.uri.lastIndexOf('%2F'));
    await fileHandler.deleteDocumentFile(file);
    hierarchyCache.remove(file, parentUri);
  }

  @override
  Future<DocumentFile?> renameDocumentFile(
      DocumentFile file, String newName) async {
    final parentUri = file.uri.substring(0, file.uri.lastIndexOf('%2F'));
    final renamedFile = await fileHandler.renameDocumentFile(file, newName);
    if (renamedFile != null) {
      hierarchyCache.rename(file, renamedFile, parentUri);
    }
    return renamedFile;
  }

  @override
  Future<DocumentFile?> copyDocumentFile(
      DocumentFile source, String destinationParentUri) async {
    final copiedFile =
        await fileHandler.copyDocumentFile(source, destinationParentUri);
    if (copiedFile != null) {
      hierarchyCache.add(copiedFile, destinationParentUri);
    }
    return copiedFile;
  }

  @override
  Future<DocumentFile?> moveDocumentFile(
      DocumentFile source, String destinationParentUri) async {
    final sourceParentUri = source.uri.substring(0, source.uri.lastIndexOf('%2F'));
    final movedFile =
        await fileHandler.moveDocumentFile(source, destinationParentUri);
    if (movedFile != null) {
      hierarchyCache.remove(source, sourceParentUri);
      hierarchyCache.add(movedFile, destinationParentUri);
    }
    return movedFile;
  }

  // --- Unchanged Delegations ---
  @override
  Future<DocumentFile?> getFileMetadata(String uri) =>
      fileHandler.getFileMetadata(uri);

  @override
  Future<List<DocumentFile>> listDirectory(String uri,
          {bool includeHidden = false}) =>
      fileHandler.listDirectory(uri, includeHidden: includeHidden);

  @override
  Future<String> readFile(String uri) => fileHandler.readFile(uri);

  @override
  Future<Uint8List> readFileAsBytes(String uri) =>
      fileHandler.readFileAsBytes(uri);

  @override
  Future<DocumentFile> writeFile(DocumentFile file, String content) =>
      fileHandler.writeFile(file, content);

  @override
  Future<DocumentFile> writeFileAsBytes(DocumentFile file, Uint8List bytes) =>
      fileHandler.writeFileAsBytes(file, bytes);
}