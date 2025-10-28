// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_storage_provider.dart
// =========================================

import 'dart:async';
import 'dart:typed_data';

import 'package:dart_git/dart_git.dart';

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

    final nonExistentFile = VirtualDocumentFile(
      uri: '${base.uri}/${relativePath.replaceAll(r'\', '/')}',
      name: relativePath.split(RegExp(r'[/\\]')).last,
    );
    return AppStorageHandle(nonExistentFile);
  }

  @override
  Stream<List<int>> read(StorageHandle handle) async* {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';
    final bytes = await _fileHandler.readFileAsBytes(handle.file.uri);
    yield bytes;
  }

  @override
  Future<Uint8List> readRange(StorageHandle handle, int start, int end) async {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';

    // This now delegates to our new, efficient FileHandler method instead of
    // reading the whole file into memory.
    return _fileHandler.readFileAsBytesRange(handle.file.uri, start, end);
  }
  
  @override
  Future<void> write(StorageHandle handle, Stream<List<int>> data) async {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';

    final parentUri = _fileHandler.getParentUri(handle.file.uri);
    final fileName = _fileHandler.getFileName(handle.file.uri);

    final bytes = await data.expand((b) => b).toList();
    final content = Uint8List.fromList(bytes);

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
    if (handle.file is! ProjectDocumentFile) {
      return;
    }
    await _fileHandler.deleteDocumentFile(handle.file as ProjectDocumentFile);
  }

  @override
  Future<void> createDirectory(StorageHandle handle, {bool recursive = false}) async {
    if (handle is! AppStorageHandle) throw 'Invalid handle type';
    final parentUri = _fileHandler.getParentUri(handle.file.uri);
    final dirName = _fileHandler.getFileName(handle.file.uri);
    await _fileHandler.createDocumentFile(parentUri, dirName, isDirectory: true);
  }

  @override
  Future<void> chmod(StorageHandle handle, int mode) async {
    return;
  }

  @override
  Future<String> relativePath(StorageHandle base, StorageHandle child) async {
    if (base is! AppStorageHandle || child is! AppStorageHandle) throw 'Invalid handle type';
    return _fileHandler.getPathForDisplay(child.file.uri, relativeTo: base.file.uri);
  }
}