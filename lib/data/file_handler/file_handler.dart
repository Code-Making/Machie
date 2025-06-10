// lib/project/file_handler/file_handler.dart

// Abstract interface for a file-like entity.
abstract class DocumentFile {
  String get uri;
  String get name;
  bool get isDirectory;
  int get size;
  DateTime get modifiedDate;
  String get mimeType;
}

// Abstract interface for file operations.
abstract class FileHandler {
  Future<DocumentFile?> pickDirectory();
  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });
  Future<DocumentFile?> pickFile();
  Future<List<DocumentFile>> pickFiles();

  Future<String> readFile(String uri);
  Future<DocumentFile> writeFile(DocumentFile file, String content);
  Future<DocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    bool overwrite = false,
  });
  Future<void> deleteDocumentFile(DocumentFile file);

  Future<DocumentFile?> renameDocumentFile(DocumentFile file, String newName);
  Future<DocumentFile?> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );
  Future<DocumentFile?> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );

  Future<DocumentFile?> getFileMetadata(String uri);
}
