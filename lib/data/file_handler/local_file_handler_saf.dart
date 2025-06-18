// lib/project/file_handler/local_file_handler_saf.dart
import 'dart:convert';
import 'dart:typed_data'; // NEW IMPORT

import 'package:flutter/services.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import 'file_handler.dart';
import 'local_file_handler.dart';

class SafFileHandler implements LocalFileHandler {
  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();

  @override
  Future<DocumentFile?> pickDirectory() async {
    final dir = await _safUtil.pickDirectory(
      persistablePermission: true,
      writePermission: true,
    );
    return dir != null ? CustomSAFDocumentFile(dir) : null;
  }

  @override
  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  }) async {
    try {
      final files = await _safUtil.list(uri);
      files.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!includeHidden) {
        files.removeWhere((f) => f.name == '.machine' && f.isDir);
      }
      return files.map((f) => CustomSAFDocumentFile(f)).toList();
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') return [];
      rethrow;
    }
  }

  @override
  Future<String> readFile(String uri) async {
    final bytes = await _safStream.readFileBytes(uri);
    return utf8.decode(bytes);
  }

  @override
  Future<Uint8List> readFileAsBytes(String uri) {
    return _safStream.readFileBytes(uri);
  }

  @override
  Future<DocumentFile> writeFile(DocumentFile file, String content) async {
    final parentUri = file.uri.substring(0, file.uri.lastIndexOf('%2F'));
    final result = await _safStream.writeFileBytes(
      parentUri,
      file.name,
      file.mimeType,
      Uint8List.fromList(utf8.encode(content)),
      overwrite: true,
    );
    final newFile = await _safUtil.documentFileFromUri(
      result.uri.toString(),
      false,
    );
    return CustomSAFDocumentFile(newFile!);
  }

  // NEW METHOD IMPLEMENTATION
  @override
  Future<DocumentFile> writeFileAsBytes(
    DocumentFile file,
    Uint8List bytes,
  ) async {
    final parentUri = file.uri.substring(0, file.uri.lastIndexOf('%2F'));
    final result = await _safStream.writeFileBytes(
      parentUri,
      file.name,
      file.mimeType,
      bytes,
      overwrite: true,
    );
    final newFile = await _safUtil.documentFileFromUri(
      result.uri.toString(),
      false,
    );
    return CustomSAFDocumentFile(newFile!);
  }

  String _inferMimeType(String fileName) {
    final ext = fileName.split('.').lastOrNull?.toLowerCase();
    return CustomSAFDocumentFile._mimeTypes[ext] ?? 'application/octet-stream';
  }

  @override
  Future<DocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  }) async {
    if (isDirectory) {
      final createdDir = await _safUtil.mkdirp(parentUri, [name]);
      return CustomSAFDocumentFile(createdDir);
    } else {
      // Prioritize raw bytes if provided, otherwise use the string content.
      final contentBytes =
          initialBytes ?? Uint8List.fromList(utf8.encode(initialContent ?? ''));
      final mimeType = _inferMimeType(name);

      final writeResponse = await _safStream.writeFileBytes(
        parentUri,
        name,
        mimeType,
        contentBytes,
        overwrite: overwrite,
      );

      final createdFile = await _safUtil.documentFileFromUri(
        writeResponse.uri.toString(),
        false,
      );
      if (createdFile == null)
        throw Exception('Failed to get metadata for created file: $name');
      return CustomSAFDocumentFile(createdFile);
    }
  }

  @override
  Future<void> deleteDocumentFile(DocumentFile file) async {
    await _safUtil.delete(file.uri, file.isDirectory);
  }

  @override
  Future<DocumentFile?> renameDocumentFile(
    DocumentFile file,
    String newName,
  ) async {
    final renamed = await _safUtil.rename(file.uri, file.isDirectory, newName);
    return renamed != null ? CustomSAFDocumentFile(renamed) : null;
  }

  // CORRECTED: This method now correctly copies any file type using raw bytes.
  @override
  Future<DocumentFile?> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  ) async {
    if (source.isDirectory)
      throw UnsupportedError('Recursive folder copy not supported.');

    // Read the file as raw bytes.
    final contentBytes = await readFileAsBytes(source.uri);

    // Create the new file using the raw bytes.
    return createDocumentFile(
      destinationParentUri,
      source.name,
      initialBytes: contentBytes,
      overwrite: true, // Typically, an import should overwrite.
    );
  }

  @override
  Future<DocumentFile?> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  ) async {
    if (source.isDirectory)
      throw UnsupportedError('Recursive folder move not supported.');
    final copied = await copyDocumentFile(source, destinationParentUri);
    if (copied != null) await deleteDocumentFile(source);
    return copied;
  }

  @override
  Future<DocumentFile?> getFileMetadata(String uri) async {
    try {
      final file = await _safUtil.documentFileFromUri(
        uri,
        false,
      ); // Assume it might be a file or dir
      return file != null ? CustomSAFDocumentFile(file) : null;
    } catch (e) {
      print('Error getting file metadata for $uri: $e');
      return null;
    }
  }

  @override
  Future<DocumentFile?> pickFile() async {
    final file = await _safUtil.pickFile();
    return file != null ? CustomSAFDocumentFile(file) : null;
  }

  @override
  Future<List<DocumentFile>> pickFiles() async {
    final files = await _safUtil.pickFiles();
    return files?.map((f) => CustomSAFDocumentFile(f)).toList() ?? [];
  }
}

class CustomSAFDocumentFile implements DocumentFile {
  final SafDocumentFile _safFile;
  CustomSAFDocumentFile(this._safFile);

  @override
  String get uri => _safFile.uri;
  @override
  String get name => _safFile.name;
  @override
  bool get isDirectory => _safFile.isDir;
  @override
  int get size => _safFile.length;
  @override
  DateTime get modifiedDate =>
      DateTime.fromMillisecondsSinceEpoch(_safFile.lastModified);
  @override
  String get mimeType =>
      _safFile.isDir
          ? 'inode/directory'
          : (_mimeTypes[name.split('.').lastOrNull?.toLowerCase()] ??
              'application/octet-stream');

  static const _mimeTypes = {
    'txt': 'text/plain',
    'dart': 'text/x-dart',
    'js': 'text/javascript',
    'json': 'application/json',
    'md': 'text/markdown',
  };
}
