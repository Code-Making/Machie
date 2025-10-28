// lib/explorer/plugins/git_explorer/git_storage_provider.dart
import 'dart:async';
import 'dart:typed_data';

// Imports from the dart_git package
import 'package:dart_git/dart_git.dart';

// Imports from the machine app
import '../../../data/file_handler/file_handler.dart';
import '../../../project/project_models.dart';

/// A custom StorageHandle that wraps the application's native DocumentFile object.
/// This is the "noun" or "pointer" that dart_git will pass around when interacting
/// with its storage provider.
class AppStorageHandle extends StorageHandle {
  final DocumentFile file;

  AppStorageHandle(this.file);

  @override
  String get name => file.name;

  @override
  String get uri => file.uri;
}

/// The implementation of the storage provider that knows how to operate on
/// AppStorageHandles. This is the "verb" or "engine" that translates dart_git's
/// abstract requests into concrete calls to our app's existing FileHandler.
class AppStorageProvider implements GitStorageProvider {
  final FileHandler _fileHandler;

  AppStorageProvider(this._fileHandler);

  @override
  Future<StorageHandle> resolve(StorageHandle base, String relativePath) async {
    if (base is! AppStorageHandle) throw 'Invalid handle type for AppStorageProvider';

    final resolvedFile = await _fileHandler.resolvePath(base.file.uri, relativePath);
    if (resolvedFile != null) {
      return AppStorageHandle(resolvedFile);
    }

    // If the file doesn't exist, create a handle to where it *would* be.
    // We can use a VirtualDocumentFile for this, as it represents a non-physical path.
    // This is necessary for operations like `write` which might create new files.
    final nonExistentFile = VirtualDocumentFile(
      // This URI construction is a simplification. A robust solution would use a
      // fileHandler.join(base.uri, relativePath) method if available.
      uri: '${base.uri}/${relativePath.replaceAll(r'\', '/')}',
      name: relativePath.split(RegExp(r'[/\\]')).last,
    );
    return AppStorageHandle(nonExistentFile);
  }

  @override
  Stream<List<int>> read(StorageHandle handle) async* {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';
    // Convert the Future<Uint8List> from our FileHandler into the Stream that dart_git requires.
    final bytes = await _fileHandler.readFileAsBytes(handle.file.uri);
    yield bytes;
  }

  @override
  Future<Uint8List> readRange(StorageHandle handle, int start, int end) async {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';

    // Our FileHandler interface doesn't support efficient random access (range reads).
    // The implementation falls back to reading the entire file and taking a sublist.
    // This is a known performance limitation for large packfiles when using SAF.
    final allBytes = await _fileHandler.readFileAsBytes(handle.file.uri);
    return allBytes.sublistView(start, end);
  }

  @override
  Future<void> write(StorageHandle handle, Stream<List<int>> data) async {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';

    // The file might not exist yet, so we use a method that can create hierarchies.
    final parentUri = _fileHandler.getParentUri(handle.file.uri);
    final fileName = _fileHandler.getFileName(handle.file.uri);

    // Collect the stream into a single byte list before writing.
    final bytes = await data.expand((b) => b).toList();
    final content = Uint8List.fromList(bytes);

    // Use a method that can create and write in one step.
    await _fileHandler.createDocumentFile(
      parentUri,
      fileName,
      initialBytes: content,
      overwrite: true,
    );
  }

  @override
  Future<List<StorageHandle>> list(StorageHandle handle) async {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';
    final children = await _fileHandler.listDirectory(handle.file.uri);
    return children.map((file) => AppStorageHandle(file)).toList();
  }

  @override
  Future<StorageStat> stat(StorageHandle handle) async {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';

    // getFileMetadata returns null if the file is not found.
    final metadata = await _fileHandler.getFileMetadata(handle.file.uri);
    if (metadata == null) {
      return StorageStat(
        type: StorageEntryType.notFound,
        size: -1,
        modificationTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }

    return StorageStat(
      type: metadata.isDirectory ? StorageEntryType.directory : StorageEntryType.file,
      size: metadata.size,
      modificationTime: metadata.modifiedDate,
    );
  }

  @override
  Future<bool> exists(StorageHandle handle) async {
    final s = await stat(handle);
    return s.type != StorageEntryType.notFound;
  }

  @override
  Future<void> delete(StorageHandle handle, {bool recursive = false}) async {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';
    // Our deleteDocumentFile handles recursion implicitly (especially for SAF).
    if (handle.file is! ProjectDocumentFile) {
      // Cannot delete a virtual file, which shouldn't happen in a real git flow.
      return;
    }
    await _fileHandler.deleteDocumentFile(handle.file as ProjectDocumentFile);
  }

  @override
  Future<void> createDirectory(StorageHandle handle, {bool recursive = false}) async {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';
    // This assumes recursive creation is handled by the underlying createDocumentFile.
    final parentUri = _fileHandler.getParentUri(handle.file.uri);
    final dirName = _fileHandler.getFileName(handle.file.uri);
    await _fileHandler.createDocumentFile(parentUri, dirName, isDirectory: true);
  }

  @override
  Future<void> chmod(StorageHandle handle, int mode) async {
    // Android's Storage Access Framework (SAF) doesn't support POSIX permissions.
    // This is a safe no-op.
    return;
  }

  @override
  Future<String> relativePath(StorageHandle base, StorageHandle child) async {
    if (base is! AppStorageHandle || child is! AppStorageHandle) throw 'Invalid handle type';
    // Delegate to the FileHandler's display path logic.
    return _fileHandler.getPathForDisplay(child.file.uri, relativeTo: base.file.uri);
  }
}