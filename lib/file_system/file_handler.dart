import 'dart:convert';
import 'dart:typed_data'; // For Uint8List

import 'package:flutter/services.dart'; // For PlatformException
import 'package:flutter_riverpod/flutter_riverpod.dart'; // For Provider
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_method_channel.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

import 'package:shared_preferences/shared_preferences.dart'; // For SharedPreferences
import '../project/project_models.dart'; // NEW: For ProjectMetadata


final fileHandlerProvider = Provider<FileHandler>((ref) {
  return SAFFileHandler();
});

abstract class DocumentFile {
  String get uri;
  String get name;
  bool get isDirectory;
  int get size;
  DateTime get modifiedDate;
  String get mimeType;
}

abstract class FileHandler {
  Future<DocumentFile?> pickDirectory();
  Future<List<DocumentFile>> listDirectory(String? uri, {bool includeHidden = false}); // MODIFIED
  Future<DocumentFile?> pickFile();
  Future<List<DocumentFile>> pickFiles();

  Future<String> readFile(String uri);
  Future<DocumentFile> writeFile(DocumentFile file, String content);
  Future<DocumentFile> createDocumentFile(String parentUri, String name, {bool isDirectory = false, String? initialContent}); // NEW
  Future<void> deleteDocumentFile(DocumentFile file); // MODIFIED

  Future<DocumentFile?> renameDocumentFile(DocumentFile file, String newName); // NEW
  Future<DocumentFile?> copyDocumentFile(DocumentFile source, String destinationParentUri); // NEW (simplified)
  Future<DocumentFile?> moveDocumentFile(DocumentFile source, String destinationParentUri); // NEW (simplified)

  Future<DocumentFile?> ensureProjectDataFolder(String projectRootUri); // NEW

  Future<void> persistRootUri(String? uri);
  Future<String?> getPersistedRootUri();

  Future<String?> getMimeType(String uri);
  Future<DocumentFile?> getFileMetadata(String uri);
}

// --------------------
//  SAF Implementation
// --------------------
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
  String get mimeType {
    if (_safFile.isDir) return 'inode/directory';
    final ext = name.split('.').lastOrNull?.toLowerCase();
    return _mimeTypes[ext] ?? 'application/octet-stream';
  }

  static const _mimeTypes = {
    'txt': 'text/plain',
    'dart': 'text/x-dart',
    'js': 'text/javascript',
    'json': 'application/json',
    'md': 'text/markdown',
    // ... add more MIME types
  };
}

class SAFFileHandler implements FileHandler {
  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();
  static const _prefsKey = 'saf_root_uri';
  static const _projectDataFolderName = '.machine'; // NEW: Hidden project folder

  SAFFileHandler();

  @override
  Future<DocumentFile?> pickDirectory() async {
    final dir = await _safUtil.pickDirectory(persistablePermission: true, writePermission: true);
    return dir != null ? CustomSAFDocumentFile(dir) : null;
  }

  @override
  Future<List<DocumentFile>> listDirectory(String? uri, {bool includeHidden = false}) async { // MODIFIED
    try {
      if (uri == null) return [];
      final files = await _safUtil.list(uri);
      files.sort((a, b) {
        if (a.isDir != b.isDir) {
          return a.isDir ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Filter out hidden .machine folder if not explicitly requested
      if (!includeHidden) {
        files.removeWhere((f) => f.name == _projectDataFolderName && f.isDir);
      }

      return files.map((f) => CustomSAFDocumentFile(f)).toList();
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        //await persistRootUri(null); // Clear persisted URI if permission lost
        return [];
      }
      rethrow;
    }
  }

  @override
  Future<String> readFile(String uri) async {
    final bytes = await _safStream.readFileBytes(uri);
    return utf8.decode(bytes);
  }

  @override
  Future<DocumentFile> writeFile(DocumentFile file, String content) async {
    final treeAndFile = splitTreeAndFileUri(file);
    final result = await _safStream.writeFileBytes(
      treeAndFile.treeUri,
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
  
  String _inferMimeType(String fileName) { // Corrected: this is a method of SAFFileHandler
    final ext = fileName.split('.').lastOrNull?.toLowerCase();
    return CustomSAFDocumentFile._mimeTypes[ext] ?? 'application/octet-stream';
  }

  @override
  Future<DocumentFile> createDocumentFile(String parentUri, String name, {bool isDirectory = false, String? initialContent}) async {
    if (isDirectory) {
      final createdDir = await _safUtil.mkdirp(parentUri, [name]);
      if (createdDir == null) {
        throw Exception('Failed to create directory: $name in $parentUri');
      }
      return CustomSAFDocumentFile(createdDir);
    } else {
      // For files, use writeFileBytes with initial content (or empty string)
      // and then get its metadata.
      final contentBytes = Uint8List.fromList(utf8.encode(initialContent ?? ''));
      final mimeType = _inferMimeType(name);

      final writeResponse = await _safStream.writeFileBytes(
        parentUri,
        name,
        mimeType,
        contentBytes,
        overwrite: false, // Ensure it creates if not exists, but doesn't overwrite accidentally
      );

      final createdFileMetadata = await _safUtil.documentFileFromUri(
        writeResponse.uri.toString(),
        false, // Specify isDir: false for a file
      );
      if (createdFileMetadata == null) {
        throw Exception('Failed to get metadata for created file: $name');
      }
      return CustomSAFDocumentFile(createdFileMetadata);
    }
  }



  @override
  Future<void> deleteDocumentFile(DocumentFile file) async { // MODIFIED
    await _safUtil.delete(file.uri, file.isDirectory);
  }

  @override
  Future<DocumentFile> renameDocumentFile(DocumentFile file, String newName) async {
    // Corrected rename signature: uri, isDir, newName
    final renamed = await _safUtil.rename(file.uri, file.isDirectory, newName);
    if (renamed == null) {
      throw Exception('Failed to rename ${file.name} to $newName');
    }
    return CustomSAFDocumentFile(renamed);
  }

  @override
  Future<DocumentFile?> copyDocumentFile(DocumentFile source, String destinationParentUri) async { // NEW (simplified)
    // SAF doesn't have a direct "copy" method for files/folders.
    // This typically involves reading the source and writing to the destination.
    // For simplicity in this example, we'll assume a basic copy operation.
    // A full implementation would need to handle folders recursively.
    if (source.isDirectory) {
      // Recursive copy for folders is complex with SAF. Placeholder for now.
      throw UnsupportedError('Recursive folder copy is not implemented for SAF.');
    } else {
      final content = await readFile(source.uri);
      return createDocumentFile(destinationParentUri, source.name, initialContent: content);
    }
  }

  @override
  Future<DocumentFile?> moveDocumentFile(DocumentFile source, String destinationParentUri) async { // NEW (simplified)
    // Similar to copy, SAF doesn't have a direct "move"
    // This would typically involve copy + delete.
    if (source.isDirectory) {
      throw UnsupportedError('Recursive folder move is not implemented for SAF.');
    } else {
      final copiedFile = await copyDocumentFile(source, destinationParentUri);
      if (copiedFile != null) {
        await deleteDocumentFile(source);
      }
      return copiedFile;
    }
  }

  @override
  Future<DocumentFile?> ensureProjectDataFolder(String projectRootUri) async { // NEW
    final projectDataDir = await _safUtil.child(projectRootUri, [_projectDataFolderName]);
    if (projectDataDir != null) {
      return CustomSAFDocumentFile(projectDataDir);
    } else {
      final createdDir = await _safUtil.mkdirp(projectRootUri, [_projectDataFolderName]);
      return createdDir != null ? CustomSAFDocumentFile(createdDir) : null;
    }
  }

  @override
  Future<void> persistRootUri(String? uri) async {
    final prefs = await SharedPreferences.getInstance();
    if (uri != null) {
      // SAF's pickDirectory with persistablePermission is the primary way
      // to persist permissions for a URI. Calling it again ensures persistence.
      
      await prefs.setString(_prefsKey, uri);
    } else {
      await prefs.remove(_prefsKey);
    }
  }

  @override
  Future<String?> getPersistedRootUri() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_prefsKey);
    if (uri == null) return null;

    final file = await _safUtil.documentFileFromUri(uri, true);
    return file?.uri;
  }

  @override
  Future<String?> getMimeType(String uri) async {
    final file = await _safUtil.documentFileFromUri(uri, false);
    return file != null ? CustomSAFDocumentFile(file).mimeType : null;
  }

  @override
  Future<DocumentFile?> getFileMetadata(String uri) async {
    final file = await _safUtil.documentFileFromUri(uri, false);
    return file != null ? CustomSAFDocumentFile(file) : null;
  }

  @override
  Future<DocumentFile?> pickFile() async {
    final file = await _safUtil.pickFile();
    return file != null ? CustomSAFDocumentFile(file) : null;
  }

  ({String treeUri}) splitTreeAndFileUri(DocumentFile docFile) {
    final fullUri = docFile.uri;
    final documentIndex = fullUri.lastIndexOf('%2F');
    if (documentIndex == -1) {
      throw ArgumentError("Invalid URI format: '/document/' not found.");
    }
    final treeUri = fullUri.substring(0, documentIndex);
    return (treeUri: treeUri);
  }

  @override
  Future<List<DocumentFile>> pickFiles() async {
    final files = await _safUtil.pickFiles();
    return files?.map((f) => CustomSAFDocumentFile(f)).toList() ?? [];
  }
}