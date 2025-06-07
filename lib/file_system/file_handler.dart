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
  Future<List<DocumentFile>> listDirectory(String? uri, {bool includeHidden = false});
  Future<DocumentFile?> pickFile();
  Future<List<DocumentFile>> pickFiles();

  Future<String> readFile(String uri);
  Future<DocumentFile> writeFile(DocumentFile file, String content);

  Future<DocumentFile?> createDocumentFile(String parentUri, String name, {bool isDirectory = false, String? initialContent}); // Changed return to nullable
  Future<DocumentFile?> renameDocumentFile(DocumentFile file, String newName); // Changed return to nullable
  Future<void> deleteDocumentFile(DocumentFile file);

  Future<DocumentFile?> copyDocumentFile(DocumentFile source, String destinationParentUri, {String? newName}); // Added newName for recursion
  Future<DocumentFile?> moveDocumentFile(DocumentFile source, String destinationParentUri, {String? newName}); // Added newName for recursion

  // These are for SAF internal permission persistence, not for project logic
  Future<void> persistRootUri(String? uri);
  Future<String?> getPersistedRootUri();

  Future<String?> getMimeType(String uri);
  Future<DocumentFile?> getFileMetadata(String uri);

  Future<DocumentFile?> ensureProjectDataFolder(String projectRootUri);
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
  static const _prefsKey = 'saf_last_picked_uri'; // Renamed to clarify its role
  static const String _projectDataFolderName = '.machine';

  SAFFileHandler();

  @override
  Future<DocumentFile?> pickDirectory() async {
    // This is the core SAF function to get a directory URI with persistent permission.
    // The URI itself is persisted internally by SAF and can be retrieved by getPersistedRootUri
    // if the user explicitly allowed it and it's the most recently picked.
    final dir = await _safUtil.pickDirectory(persistablePermission: true, writePermission: true);
    // Even if user cancels, it often returns null, so no need for explicit pop.
    // The issue was on the Flutter side not dismissing UI.
    return dir != null ? CustomSAFDocumentFile(dir) : null;
  }

  @override
  Future<List<DocumentFile>> listDirectory(String? uri, {bool includeHidden = false}) async {
    try {
      if (uri == null) return [];
      final files = await _safUtil.list(uri);
      files.sort((a, b) {
        if (a.isDir != b.isDir) {
          return a.isDir ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (!includeHidden) {
        files.removeWhere((f) => f.name == _projectDataFolderName && f.isDir);
      }

      return files.map((f) => CustomSAFDocumentFile(f)).toList();
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        // If permission is explicitly denied, clear the remembered URI
        await _prefs.remove(_prefsKey);
        print('SAF permission denied for $uri. Clearing persisted URI.');
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
    final treeUri = splitTreeAndFileUri(file).treeUri;
    final writeResponse = await _safStream.writeFileBytes(
      treeUri,
      file.name,
      file.mimeType,
      Uint8List.fromList(utf8.encode(content)),
      overwrite: true,
    );

    final newFile = await _safUtil.documentFileFromUri(
      writeResponse.uri.toString(),
      false,
    );
    if (newFile == null) {
      throw Exception('Failed to get metadata for written file: ${file.name}');
    }
    return CustomSAFDocumentFile(newFile);
  }

  String _inferMimeType(String fileName) {
    final ext = fileName.split('.').lastOrNull?.toLowerCase();
    return CustomSAFDocumentFile._mimeTypes[ext] ?? 'application/octet-stream';
  }

  @override
  Future<DocumentFile?> createDocumentFile(String parentUri, String name, {bool isDirectory = false, String? initialContent}) async {
    if (isDirectory) {
      final createdDir = await _safUtil.mkdir(parentUri, name); // Corrected to mkdir, not mkdirp if parentUri is already the direct parent. If parent is missing, mkdirp is suitable.
      if (createdDir == null) {
        throw Exception('Failed to create directory: $name in $parentUri');
      }
      return CustomSAFDocumentFile(createdDir);
    } else {
      final contentBytes = Uint8List.fromList(utf8.encode(initialContent ?? ''));
      final mimeType = _inferMimeType(name);

      final writeResponse = await _safStream.writeFileBytes(
        parentUri,
        name,
        mimeType,
        contentBytes,
        overwrite: false, // This will ensure creation if file doesn't exist
      );

      final createdFileMetadata = await _safUtil.documentFileFromUri(
        writeResponse.uri.toString(),
        false,
      );
      if (createdFileMetadata == null) {
        throw Exception('Failed to get metadata for created file: $name');
      }
      return CustomSAFDocumentFile(createdFileMetadata);
    }
  }

  @override
  Future<DocumentFile?> renameDocumentFile(DocumentFile file, String newName) async {
    final renamed = await _safUtil.rename(file.uri, file.isDirectory, newName);
    if (renamed == null) {
      throw Exception('Failed to rename ${file.name} to $newName');
    }
    return CustomSAFDocumentFile(renamed);
  }

  @override
  Future<void> deleteDocumentFile(DocumentFile file) async {
    await _safUtil.delete(file.uri, file.isDirectory);
  }

  @override
  Future<DocumentFile?> copyDocumentFile(DocumentFile source, String destinationParentUri, {String? newName}) async {
    final actualNewName = newName ?? source.name;

    // Check if target exists and delete it to ensure a clean copy/overwrite
    final existingTarget = await _safUtil.child(destinationParentUri, [actualNewName]);
    if (existingTarget != null) {
      await _safUtil.delete(existingTarget.uri, existingTarget.isDir);
    }

    if (!source.isDirectory) {
      final content = await readFile(source.uri);
      final writeResponse = await _safStream.writeFileBytes(
        destinationParentUri,
        actualNewName,
        source.mimeType,
        Uint8List.fromList(utf8.encode(content)),
        overwrite: true, // Overwrite if it existed and was deleted, or create new.
      );
      return await _safUtil.documentFileFromUri(writeResponse.uri.toString(), false).then((f) => CustomSAFDocumentFile(f!));
    } else {
      // Recursive copy for folders
      final newDir = await _safUtil.mkdir(destinationParentUri, actualNewName);
      if (newDir == null) throw Exception('Failed to create directory for copy destination');

      final contents = await listDirectory(source.uri, includeHidden: true);
      for (final child in contents) {
        if (child.isDirectory) {
          await copyDocumentFile(child, newDir.uri, newName: child.name); // Recursive call
        } else {
          final childContent = await readFile(child.uri);
          await _safStream.writeFileBytes(
            newDir.uri,
            child.name,
            child.mimeType,
            Uint8List.fromList(utf8.encode(childContent)),
            overwrite: true,
          );
        }
      }
      return CustomSAFDocumentFile(newDir);
    }
  }

  @override
  Future<DocumentFile?> moveDocumentFile(DocumentFile source, String destinationParentUri, {String? newName}) async {
    final actualNewName = newName ?? source.name;
    final moved = await _safUtil.move(source.uri, destinationParentUri, actualNewName);
    if (moved == null) {
      // If direct move fails (e.g., across different SAF trees), try copy + delete
      print('Direct SAF move failed for ${source.name}, attempting copy+delete fallback.');
      final copied = await copyDocumentFile(source, destinationParentUri, newName: actualNewName);
      if (copied != null) {
        await deleteDocumentFile(source);
        return copied;
      }
      throw Exception('Failed to move ${source.name} to $destinationParentUri even with copy+delete fallback.');
    }
    return CustomSAFDocumentFile(moved);
  }

  @override
  Future<void> persistRootUri(String? uri) async {
    final prefs = await SharedPreferences.getInstance();
    if (uri != null) {
      // This is for SAF to remember the *last URI opened* across app restarts.
      // It's mostly for the SAF picker to open at a familiar location.
      // The explicit `pickDirectory` call below is essential for SAF permissions.
      await _safUtil.pickDirectory(
        initialUri: uri,
        persistablePermission: true,
        writePermission: true,
      );
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

    // Verify SAF still has access to this URI
    // SAF usually maintains permissions itself, but explicit check is safer.
    final file = await _safUtil.documentFileFromUri(uri, true); // Assuming it was a directory
    return file?.uri;
  }

  @override
  Future<String?> getMimeType(String uri) async {
    final file = await _safUtil.documentFileFromUri(uri, null);
    return file != null ? CustomSAFDocumentFile(file).mimeType : null;
  }

  @override
  Future<DocumentFile?> getFileMetadata(String uri) async {
    final file = await _safUtil.documentFileFromUri(uri, null);
    return file != null ? CustomSAFDocumentFile(file) : null;
  }

  @override
  Future<DocumentFile?> pickFile() async {
    // This helper should also have a `finally` block to pop the Flutter UI if needed.
    // However, the `saf_util` methods for picking typically handle their own UI.
    final file = await _safUtil.pickFile();
    return file != null ? CustomSAFDocumentFile(file) : null;
  }

  ({String treeUri}) splitTreeAndFileUri(DocumentFile docFile) {
    final fullUri = docFile.uri;
    final documentPathSegment = '/document/';
    final treePathSegment = '/tree/'; // New base for SAF
    final primaryPathSegment = 'primary%3A'; // Common for internal storage

    final docIndex = fullUri.indexOf(documentPathSegment);
    final treeIndex = fullUri.indexOf(treePathSegment);

    if (docIndex != -1) {
      // Case 1: Standard document URI (e.g., content://.../document/primary%3ADOCS%2Ffile.txt)
      // The tree URI is everything BEFORE '/document/'
      return (treeUri: fullUri.substring(0, docIndex));
    } else if (treeIndex != -1) {
      // Case 2: Direct tree URI (e.g., content://.../tree/primary%3ADOCS)
      // This is often the URI returned by pickDirectory.
      // It may or may not contain a path after 'primary%3A'.
      // If it contains 'primary%3A' it's usually the root of the picked tree.
      final pathAfterTree = fullUri.substring(treeIndex + treePathSegment.length);
      final firstSlashAfterPrimary = pathAfterTree.indexOf('%2F');
      
      if (firstSlashAfterPrimary != -1) {
        // It's like 'primary%3ADOCS%2Fsome_folder', so the tree root is 'primary%3ADOCS'
        final rootTreeId = pathAfterTree.substring(0, firstSlashAfterPrimary);
        return (treeUri: fullUri.substring(0, treeIndex + treePathSegment.length) + rootTreeId);
      } else {
        // It's just 'primary%3ADOCS', so the whole thing is the tree URI.
        return (treeUri: fullUri);
      }
    } else {
      // Fallback: If neither standard pattern is found, this URI might be malformed
      // or refer to something non-SAF managed (e.g., a direct file path not via SAF).
      // For this app, it implies an error in URI handling or assumption.
      throw ArgumentError("Unsupported SAF URI format for tree extraction: $fullUri");
    }
  }

  @override
  Future<List<DocumentFile>> pickFiles() async {
    final files = await _safUtil.pickFiles();
    return files?.map((f) => CustomSAFDocumentFile(f)).toList() ?? [];
  }

  @override
  Future<DocumentFile?> ensureProjectDataFolder(String projectRootUri) async {
    // The path to the .machine folder
    final projectDataFolderPath = '$_projectDataFolderName'; // Directly under the root, not nested

    // Try to get the existing .machine folder
    final existingMachineFolder = await _safUtil.child(projectRootUri, [projectDataFolderPath]);

    if (existingMachineFolder != null && existingMachineFolder.isDir) {
      return CustomSAFDocumentFile(existingMachineFolder);
    } else {
      // If it doesn't exist or isn't a directory, create it
      final createdDir = await _safUtil.mkdir(projectRootUri, projectDataFolderPath);
      return createdDir != null ? CustomSAFDocumentFile(createdDir) : null;
    }
  }
}