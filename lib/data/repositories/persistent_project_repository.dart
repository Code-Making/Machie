// lib/data/repositories/persistent_project_repository.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import 'project_repository.dart';

const _projectFileName = 'project.json';

class PersistentProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final String _projectDataPath;

  PersistentProjectRepository(this.fileHandler, this._projectDataPath);

  // ... loadProject and saveProject are unchanged ...
  @override
  Future<Project> loadProject(ProjectMetadata metadata) async {
    // ...
  }
  @override
  Future<void> saveProject(Project project) async {
    // ...
  }

  // --- REFACTORED File Operations ---
  @override
  Future<DocumentFile> createDocumentFile(Ref ref, String parentUri, String name,
      {bool isDirectory = false,
      String? initialContent,
      Uint8List? initialBytes,
      bool overwrite = false}) async {
    final newFile = await fileHandler.createDocumentFile(parentUri, name,
        isDirectory: isDirectory,
        initialContent: initialContent,
        initialBytes: initialBytes,
        overwrite: overwrite);
    ref.read(projectHierarchyProvider.notifier).add(newFile, parentUri);
    // Publish event
    ref.read(fileOperationStreamProvider.notifier).add(FileCreateEvent(createdFile: newFile));
    return newFile;
  }

  @override
  Future<void> deleteDocumentFile(Ref ref, DocumentFile file) async {
    final parentUri = file.uri.substring(0, file.uri.lastIndexOf('%2F'));
    await fileHandler.deleteDocumentFile(file);
    ref.read(projectHierarchyProvider.notifier).remove(file, parentUri);
    // Publish event
    ref.read(fileOperationStreamProvider.notifier).add(FileDeleteEvent(deletedFile: file));
  }

  @override
  Future<DocumentFile?> renameDocumentFile(
      Ref ref, DocumentFile file, String newName) async {
    final parentUri = file.uri.substring(0, file.uri.lastIndexOf('%2F'));
    final renamedFile = await fileHandler.renameDocumentFile(file, newName);
    if (renamedFile != null) {
      ref.read(projectHierarchyProvider.notifier).rename(file, renamedFile, parentUri);
      // Publish event
      ref.read(fileOperationStreamProvider.notifier).add(FileRenameEvent(oldFile: file, newFile: renamedFile));
    }
    return renamedFile;
  }

  @override
  Future<DocumentFile?> copyDocumentFile(
      Ref ref, DocumentFile source, String destinationParentUri) async {
    final copiedFile =
        await fileHandler.copyDocumentFile(source, destinationParentUri);
    if (copiedFile != null) {
      ref.read(projectHierarchyProvider.notifier).add(copiedFile, destinationParentUri);
      // Publish event
      ref.read(fileOperationStreamProvider.notifier).add(FileCreateEvent(createdFile: copiedFile));
    }
    return copiedFile;
  }

  @override
  Future<DocumentFile?> moveDocumentFile(
      Ref ref, DocumentFile source, String destinationParentUri) async {
    final sourceParentUri = source.uri.substring(0, source.uri.lastIndexOf('%2F'));
    final movedFile =
        await fileHandler.moveDocumentFile(source, destinationParentUri);
    if (movedFile != null) {
      ref.read(projectHierarchyProvider.notifier).remove(source, sourceParentUri);
      ref.read(projectHierarchyProvider.notifier).add(movedFile, destinationParentUri);
      // Publish event (a move is just a rename to a new location)
      ref.read(fileOperationStreamProvider.notifier).add(FileRenameEvent(oldFile: source, newFile: movedFile));
    }
    return movedFile;
  }

  // --- Unchanged Delegations ---
  @override
  Future<DocumentFile?> getFileMetadata(String uri) => fileHandler.getFileMetadata(uri);
  @override
  Future<List<DocumentFile>> listDirectory(String uri, {bool includeHidden = false}) => fileHandler.listDirectory(uri, includeHidden: includeHidden);
  @override
  Future<String> readFile(String uri) => fileHandler.readFile(uri);
  @override
  Future<Uint8List> readFileAsBytes(String uri) => fileHandler.readFileAsBytes(uri);
  @override
  Future<DocumentFile> writeFile(DocumentFile file, String content) => fileHandler.writeFile(file, content);
  @override
  Future<DocumentFile> writeFileAsBytes(DocumentFile file, Uint8List bytes) => fileHandler.writeFileAsBytes(file, bytes);
}