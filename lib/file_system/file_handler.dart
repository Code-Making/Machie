import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<List<DocumentFile>> listDirectory(String? uri);
  Future<DocumentFile?> pickFile();
  Future<List<DocumentFile>> pickFiles();

  Future<String> readFile(String uri);
  Future<DocumentFile> writeFile(DocumentFile file, String content);
  Future<DocumentFile> createFile(String parentUri, String fileName);
  Future<void> deleteFile(String uri);

  Future<void> persistRootUri(String? uri);
  Future<String?> getPersistedRootUri();

  Future<String?> getMimeType(String uri);
  Future<DocumentFile?> getFileMetadata(String uri);
}

// --------------------
//  SAF Implementation
// --------------------
class CustomSAFDocumentFile implements DocumentFile {
  //  final CustomSAFDocumentFile _file;
  final SafDocumentFile _safFile;

  CustomSAFDocumentFile(this._safFile); // Accept SafDocumentFile

  @override
  String get uri => _safFile.uri;

  @override
  String get name => _safFile.name;

  @override
  bool get isDirectory => _safFile.isDir; // Match SAF package's property name

  @override
  int get size => _safFile.length; // SAF uses 'length' for size

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
    // ... add more MIME types
  };
}

class SAFFileHandler implements FileHandler {
  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();
  static const _prefsKey = 'saf_root_uri';

  SAFFileHandler();

  @override
  Future<DocumentFile?> pickDirectory() async {
    final dir = await _safUtil.pickDirectory(persistablePermission: true, writePermission: true,);
    return dir != null ? CustomSAFDocumentFile(dir) : null;
  }

  /* @override
  Future<List<DocumentFile>> listDirectory(String? uri) async {
    try {
      final contents = await _safUtil.list(uri ?? '');

      contents.sort((a, b) {
        if (a.isDir != b.isDir) {
          return a.isDir ? -1 : 1;
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return contents.map((f) => CustomSAFDocumentFile(f)).toList();
    } catch (e) {
      print('Error listing directory: $e');
      return [];
    }
  }*/

  @override
  Future<List<DocumentFile>> listDirectory(String? uri) async {
    try {
      if (uri == null) return [];
      final files = await _safUtil.list(uri);
      files.sort((a, b) {
        if (a.isDir != b.isDir) {
          return a.isDir ? -1 : 1;
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return files.map((f) => CustomSAFDocumentFile(f)).toList();
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        await persistRootUri(null);
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
    // Write file using SAF
    final treeAndFile = splitTreeAndFileUri(file);
    print(treeAndFile);
    final result = await _safStream.writeFileBytes(
      treeAndFile.treeUri, // Parent directory URI
      file.name, // Original file name
      file.mimeType,
      Uint8List.fromList(utf8.encode(content)),
      overwrite: true,
    );

    // Get updated document metadata
    final newFile = await _safUtil.documentFileFromUri(
      result.uri.toString(),
      false,
    );

    return CustomSAFDocumentFile(newFile!);
  }

  @override
  Future<DocumentFile> createFile(String parentUri, String fileName) async {
    final file = await _safUtil.child(parentUri, [fileName]);
    if (file == null) {
      final created = await _safUtil.mkdirp(parentUri, [fileName]);
      return CustomSAFDocumentFile(created!);
    }
    return CustomSAFDocumentFile(file);
  }

  @override
  Future<void> deleteFile(String uri) async {
    await _safUtil.delete(uri, false);
  }

  @override
  Future<void> persistRootUri(String? uri) async {
    if (true) return;
    if (uri != null) {
      // Take persistable permissions
      await _safUtil.pickDirectory(
        initialUri: uri,
        persistablePermission: true,
        writePermission: true,
      );
    }
  }

  @override
  Future<String?> getPersistedRootUri() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_prefsKey);
    if (uri == null) return null;

    // Verify we still have access
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


  ({String treeUri/*, String fileUri, String relativePath*/}) splitTreeAndFileUri(DocumentFile docFile) {
  // Extract the Tree URI (everything before '/document/')
  final fullUri = docFile.uri;
  final documentIndex = fullUri.lastIndexOf('%2F');
  if (documentIndex == -1) {
    throw ArgumentError("Invalid URI format: '/document/' not found.");
  }

  final treeUri = fullUri.substring(0, documentIndex);
  /*// Extract the File URI (everything after '/document/')
  final fileUri = fullUri.substring(documentIndex + '/document/'.length);
  
  // Extract the relative path (remove the repeated tree part if needed)
  final treePath = treeUri.substring(treeUri.indexOf('/tree/') + '/tree/'.length);
  String relativePath = fileUri;
  
  // If the fileUri starts with the same path as the treeUri, remove it
  if (fileUri.startsWith(treePath)) {
    relativePath = fileUri.substring(treePath.length);
  }*/
  
  return (treeUri: treeUri);
}

  @override
  Future<List<DocumentFile>> pickFiles() async {
    final files = await _safUtil.pickFiles();
    return files?.map((f) => CustomSAFDocumentFile(f)).toList() ?? [];
  }
}