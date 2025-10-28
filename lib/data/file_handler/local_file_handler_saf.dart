import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

import 'file_handler.dart';
import 'local_file_handler.dart';

class CustomSAFDocumentFile extends ProjectDocumentFile {
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

class SafFileHandler implements LocalFileHandler {
  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();
  // THE FIX: Implement the new interface methods with SAF-specific logic.
  static const String _separator = '%2F';

  @override
  Future<bool> hasPermission(String uri) async {
    // getPersistedUriPermissions returns a list of all URIs the app
    // currently has permission to access.
    final permissions = await _safUtil.hasPersistedPermission(
      uri,
      checkRead: true,
      checkWrite: true,
    );
    if (permissions == false) {
      return false;
    }

    try {
      // We don't care about the result, only that it doesn't throw.
      final stat = await _safUtil.stat(
        uri,
        true,
      ); // `true` because we are checking a directory.
      if (stat != null) {
        return true;
      } else {
        return false;
      }
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        // The permission is stale or not honored by the provider.
        return false;
      }
      // Another error occurred (e.g., URI not found), but it's not a
      // permission issue from our perspective. For the purpose of this check,
      // we can consider it as if we don't have effective permission.
      return false;
    } catch (_) {
      // Catch any other unexpected errors.
      return false;
    }
  }

  @override
  Future<bool> reRequestPermission(String uri) async {
    // Re-trigger the directory picker. The user must manually navigate to and
    // select the same folder again.
    final dir = await _safUtil.pickDirectory(
      persistablePermission: true,
      writePermission: true,
    );

    // Check if the user selected a directory and if it matches the one we need.
    if (dir != null && dir.uri == uri) {
      // Permission was successfully granted for the correct directory.
      return true;
    }
    // The user cancelled or selected the wrong directory.
    return false;
  }

  @override
  Future<ProjectDocumentFile?> pickDirectory() async {
    final dir = await _safUtil.pickDirectory(
      persistablePermission: true,
      writePermission: true,
    );
    return dir != null ? CustomSAFDocumentFile(dir) : null;
  }

  @override
  Future<List<ProjectDocumentFile>> listDirectory(
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
        files.removeWhere((f) => f.name.startsWith('.') && f.isDir);
      }
      return files.map((f) => CustomSAFDocumentFile(f)).toList();
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        // Translate to our custom exception
        throw PermissionDeniedException(uri: uri);
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
  Future<Uint8List> readFileAsBytes(String uri) {
    return _safStream.readFileBytes(uri);
  }
  
  @override
  Future<Uint8List> readFileAsBytesRange(String uri, int start, int end) {
    if (start < 0 || end <= start) {
      throw ArgumentError('Invalid range: start=$start, end=$end');
    }
    // Convert our 'end' offset to the 'count' parameter required by saf_stream.
    final count = end - start;
    return _safStream.readFileBytes(uri, start: start, count: count);
  }

  @override
  Future<ProjectDocumentFile> writeFile(
    ProjectDocumentFile file,
    String content,
  ) async {
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

  @override
  Future<ProjectDocumentFile> writeFileAsBytes(
    ProjectDocumentFile file,
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
  Future<ProjectDocumentFile> createDocumentFile(
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
      if (createdFile == null) {
        throw Exception('Failed to get metadata for created file: $name');
      }
      return CustomSAFDocumentFile(createdFile);
    }
  }

  @override
  Future<void> deleteDocumentFile(ProjectDocumentFile file) async {
    await _safUtil.delete(file.uri, file.isDirectory);
  }

  // THE FIX: Implemented robust rename with fallback.
  @override
  Future<ProjectDocumentFile> renameDocumentFile(
    ProjectDocumentFile file,
    String newName,
  ) async {
    try {
      // 1. Attempt the efficient, native rename first.
      final renamed = await _safUtil.rename(
        file.uri,
        file.isDirectory,
        newName,
      );
      return CustomSAFDocumentFile(renamed);
    } on PlatformException catch (e) {
      // 2. If it fails, log it and fall back to a manual copy-delete.
      debugPrint(
        'Native rename failed: ${e.message}. Falling back to manual rename.',
      );

      // Fallback for directories is not supported as it requires recursion.
      if (file.isDirectory) {
        throw Exception(
          'Renaming this folder is not supported on your device.',
        );
      }

      // Fallback logic for files:
      final parentUri = file.uri.substring(0, file.uri.lastIndexOf('%2F'));
      final bytes = await readFileAsBytes(file.uri);
      final newFile = await createDocumentFile(
        parentUri,
        newName,
        initialBytes: bytes,
      );
      await deleteDocumentFile(file);
      return newFile;
    }
  }

  // `copyDocumentFile` remains the same, as it already uses the stream-based method.
  @override
  Future<ProjectDocumentFile> copyDocumentFile(
    ProjectDocumentFile source,
    String destinationParentUri,
  ) async {
    if (source.isDirectory) {
      throw UnsupportedError('Recursive folder copy is not yet supported.');
    }
    final contentBytes = await readFileAsBytes(source.uri);
    return createDocumentFile(
      destinationParentUri,
      source.name,
      initialBytes: contentBytes,
      overwrite: true,
    );
  }

  // THE FIX: Implemented robust move with fallback.
  @override
  Future<ProjectDocumentFile> moveDocumentFile(
    ProjectDocumentFile source,
    String destinationParentUri,
  ) async {
    try {
      // 1. Attempt the efficient, native move first.
      final sourceParentUri = source.uri.substring(
        0,
        source.uri.lastIndexOf('%2F'),
      );
      final movedFile = await _safUtil.moveTo(
        source.uri,
        source.isDirectory,
        sourceParentUri,
        destinationParentUri,
      );
      return CustomSAFDocumentFile(movedFile);
    } on PlatformException catch (e) {
      // 2. If it fails, log it and fall back to a manual copy-delete.
      debugPrint(
        'Native move failed: ${e.message}. Falling back to manual move.',
      );

      // Fallback for directories is not supported as it requires recursion.
      if (source.isDirectory) {
        throw Exception('Moving this folder is not supported on your device.');
      }

      // Fallback logic for files:
      final copiedFile = await copyDocumentFile(source, destinationParentUri);
      await deleteDocumentFile(source);
      return copiedFile;
    }
  }

  @override
  Future<ProjectDocumentFile?> resolvePath(
    String parentUri,
    String relativePath,
  ) async {
    final segments =
        relativePath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return getFileMetadata(parentUri);
    }

    ProjectDocumentFile? currentParent;
    try {
      // Ensure the starting parent directory exists.
      final stat = await _safUtil.stat(parentUri, true);
      if (stat == null) return null;
      currentParent = CustomSAFDocumentFile(stat);
    } catch (_) {
      return null;
    }

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLastSegment = i == segments.length - 1;

      try {
        final children = await listDirectory(currentParent!.uri);
        final foundChild = children.firstWhereOrNull(
          (child) => child.name == segment,
        );

        if (foundChild == null) {
          return null; // Path segment not found
        }

        if (isLastSegment) {
          return foundChild; // Success: Found the final file/folder
        } else if (foundChild.isDirectory) {
          currentParent = foundChild; // Continue traversal
        } else {
          return null; // A file was found in the middle of the path, which is invalid.
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  Future<ProjectDocumentFile> createDirectoryAndFile(
    String parentUri,
    String relativePath, {
    String? initialContent,
  }) async {
    final segments =
        relativePath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw ArgumentError('Relative path cannot be empty.');
    }
    final fileName = segments.last;
    final directorySegments =
        segments.length > 1
            ? segments.sublist(0, segments.length - 1)
            : <String>[];
    String finalParentUri =
        directorySegments.isNotEmpty
            ? (await _safUtil.mkdirp(parentUri, directorySegments)).uri
            : parentUri;
    return createDocumentFile(
      finalParentUri,
      fileName,
      isDirectory: false,
      initialContent: initialContent ?? '',
    );
  }

  @override
  Future<ProjectDocumentFile?> getFileMetadata(String uri) async {
    try {
      final file = await _safUtil.stat(uri, false);
      return file != null ? CustomSAFDocumentFile(file) : null;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        throw PermissionDeniedException(uri: uri);
      }
      rethrow;
    }
  }

  @override
  Future<ProjectDocumentFile?> pickFile() async {
    final file = await _safUtil.pickFile();
    return file != null ? CustomSAFDocumentFile(file) : null;
  }

  @override
  Future<List<ProjectDocumentFile>> pickFiles() async {
    final files = await _safUtil.pickFiles();
    return files?.map((f) => CustomSAFDocumentFile(f)).toList() ?? [];
  }

  @override
  String getParentUri(String uri) {
    final lastIndex = uri.lastIndexOf(_separator);
    // If there's no separator or it's a root URI, there's no parent to return.
    // In SAF, a root might not have a parent we can navigate "up" to.
    if (lastIndex == -1 || !uri.substring(0, lastIndex).contains(_separator)) {
      return uri;
    }
    return uri.substring(0, lastIndex);
  }

  @override
  String getFileName(String uri) {
    return uri.split(_separator).last;
  }

  @override
  String getPathForDisplay(String uri, {String? relativeTo}) {
    String path = uri;
    if (relativeTo != null && path.startsWith(relativeTo)) {
      path = path.substring(relativeTo.length);
      if (path.startsWith(_separator)) {
        path = path.substring(_separator.length);
      }
    }
    return path.split(_separator).map((s) => Uri.decodeComponent(s)).join('/');
  }
}
