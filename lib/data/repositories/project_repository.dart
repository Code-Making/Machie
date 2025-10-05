import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../file_handler/file_handler.dart';
import '../../logs/logs_provider.dart';
import '../dto/project_dto.dart';

// ... (FileOperationEvent and related providers are unchanged) ...
sealed class FileOperationEvent {
  const FileOperationEvent();
}

class FileCreateEvent extends FileOperationEvent {
  final DocumentFile createdFile;
  const FileCreateEvent({required this.createdFile});
}

class FileRenameEvent extends FileOperationEvent {
  final DocumentFile oldFile;
  final DocumentFile newFile;
  const FileRenameEvent({required this.oldFile, required this.newFile});
}

class FileDeleteEvent extends FileOperationEvent {
  final DocumentFile deletedFile;
  const FileDeleteEvent({required this.deletedFile});
}

final fileOperationControllerProvider =
    Provider<StreamController<FileOperationEvent>>((ref) {
      final controller = StreamController<FileOperationEvent>.broadcast();
      ref.onDispose(() => controller.close());
      return controller;
    });

final fileOperationStreamProvider =
    StreamProvider.autoDispose<FileOperationEvent>((ref) {
      return ref.watch(fileOperationControllerProvider).stream;
    });

// REMOVED projectHierarchyProvider

final projectRepositoryProvider = StateProvider<ProjectRepository?>(
  (ref) => null,
);

// ... (ProjectRepository abstract class is unchanged) ...
abstract class ProjectRepository {
  FileHandler get fileHandler;
  Future<ProjectDto> loadProjectDto();
  Future<void> saveProjectDto(ProjectDto projectDto);
  Future<DocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  });
  Future<void> deleteDocumentFile(DocumentFile file);
  
  Future<DocumentFile> renameDocumentFile(
    DocumentFile file,
    String newName,
  );
  Future<DocumentFile> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );
  Future<DocumentFile> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );

  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });
  Future<String> readFile(String uri);
  Future<Uint8List> readFileAsBytes(String uri);
  Future<DocumentFile> writeFile(DocumentFile file, String content);
  Future<DocumentFile> writeFileAsBytes(DocumentFile file, Uint8List bytes);
  Future<DocumentFile?> getFileMetadata(String uri);
}