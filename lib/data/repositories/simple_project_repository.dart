// =========================================
// FILE: lib/data/repositories/simple_project_repository.dart
// =========================================

// lib/data/repositories/simple_project_repository.dart
import 'dart:typed_data';
// import 'package:flutter_riverpod/flutter_riverpod.dart'; // REMOVED
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import 'project_repository.dart';

class SimpleProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final Map<String, dynamic>? _projectStateJson;

  SimpleProjectRepository(this.fileHandler, this._projectStateJson);

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

  // REFACTORED: Methods are now pure data operations.
  @override
  Future<DocumentFile> createDocumentFile(
    // REMOVED: Ref ref,
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  }) async {
    final newFile = await fileHandler.createDocumentFile(
      parentUri,
      name,
      isDirectory: isDirectory,
      initialContent: initialContent,
      initialBytes: initialBytes,
      overwrite: overwrite,
    );
    // REMOVED: All ref.read() calls. This logic moves to the service layer.
    return newFile;
  }

  @override
  Future<void> deleteDocumentFile(/* REMOVED: Ref ref,*/ DocumentFile file) async {
    // REMOVED: parentUri calculation and ref.read() calls. This moves to the service.
    await fileHandler.deleteDocumentFile(file);
  }

  @override
  Future<DocumentFile?> renameDocumentFile(
    // REMOVED: Ref ref,
    DocumentFile file,
    String newName,
  ) async {
    final renamedFile = await fileHandler.renameDocumentFile(file, newName);
    // REMOVED: All ref.read() calls. This logic moves to the service layer.
    return renamedFile;
  }

  @override
  Future<DocumentFile?> copyDocumentFile(
    // REMOVED: Ref ref,
    DocumentFile source,
    String destinationParentUri,
  ) async {
    final copiedFile = await fileHandler.copyDocumentFile(
      source,
      destinationParentUri,
    );
    // REMOVED: All ref.read() calls. This logic moves to the service layer.
    return copiedFile;
  }

  @override
  Future<DocumentFile?> moveDocumentFile(
    // REMOVED: Ref ref,
    DocumentFile source,
    String destinationParentUri,
  ) async {
    final movedFile = await fileHandler.moveDocumentFile(
      source,
      destinationParentUri,
    );
    // REMOVED: All ref.read() calls. This logic moves to the service layer.
    return movedFile;
  }

  // --- Unchanged Delegations ---
  @override
  Future<DocumentFile?> getFileMetadata(String uri) =>
      fileHandler.getFileMetadata(uri);
  @override
  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  }) => fileHandler.listDirectory(uri, includeHidden: includeHidden);
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