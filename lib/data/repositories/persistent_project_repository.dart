// lib/data/repositories/persistent_project_repository.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import 'project_hierarchy_cache.dart';
import 'project_repository.dart';

const _projectFileName = 'project.json';

/// REFACTOR: Concrete implementation for projects that save their state
/// to a `.machine/` directory in the file system.
class PersistentProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final String _projectDataPath;

  // REFACTOR: The repository now creates and owns the hierarchy cache.
  @override
  late final ProjectHierarchyCache hierarchyCache;

  PersistentProjectRepository(
    this.fileHandler,
    this._projectDataPath,
    Ref ref, // REFACTOR: Pass ref to get Talker for the cache.
  ) {
    hierarchyCache = ProjectHierarchyCache(fileHandler, ref.read(talkerProvider));
  }

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

  // --- REFACTORED File Operations ---
  // Each method now updates the cache after the file system operation succeeds.

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
    // We need to find the parent URI before deleting
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