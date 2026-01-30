import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

import 'file_handler.dart';
import 'local_file_handler.dart';

import 'package:path/path.dart' as p;

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
  static const String _separator = '%2F';

  final String rootUri;

  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();

  final p.Context _pathContext = p.Context(style: p.Style.posix);

  SafFileHandler(this.rootUri);

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

  @override
  Future<ProjectDocumentFile> renameDocumentFile(
    ProjectDocumentFile file,
    String newName,
  ) async {
    try {
      final renamed = await _safUtil.rename(
        file.uri,
        file.isDirectory,
        newName,
      );
      return CustomSAFDocumentFile(renamed);
    } on PlatformException catch (e) {
      debugPrint(
        'Native rename failed: ${e.message}. Falling back to manual rename.',
      );

      if (file.isDirectory) {
        throw Exception(
          'Renaming this folder is not supported on your device.',
        );
      }

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

  @override
  Future<ProjectDocumentFile> moveDocumentFile(
    ProjectDocumentFile source,
    String destinationParentUri,
  ) async {
    try {
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
      debugPrint(
        'Native move failed: ${e.message}. Falling back to manual move.',
      );

      if (source.isDirectory) {
        throw Exception('Moving this folder is not supported on your device.');
      }

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
        relativePath
            .replaceAll(r'\', '/')
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList();
    if (segments.isEmpty) {
      return getFileMetadata(parentUri);
    }

    String currentUri = parentUri;

    for (final segment in segments) {
      if (segment == '.') {
        continue;
      } else if (segment == '..') {
        currentUri = getParentUri(currentUri);
      } else {
        try {
          final children = await listDirectory(currentUri, includeHidden: true);
          final foundChild = children.firstWhereOrNull(
            (child) => child.name == segment,
          );

          if (foundChild != null) {
            currentUri = foundChild.uri;
          } else {
            return null;
          }
        } catch (_) {
          return null;
        }
      }
    }

    return getFileMetadata(currentUri);
  }

  @override
  Future<({ProjectDocumentFile file, List<ProjectDocumentFile> createdDirs})>
  createDirectoryAndFile(
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

    final List<ProjectDocumentFile> createdDirs = [];
    String currentParentUri = parentUri;

    for (final segment in directorySegments) {
      final existingDir = await resolvePath(currentParentUri, segment);
      if (existingDir != null && existingDir.isDirectory) {
        currentParentUri = existingDir.uri;
      } else {
        final newDir = await createDocumentFile(
          currentParentUri,
          segment,
          isDirectory: true,
        );
        createdDirs.add(newDir);
        currentParentUri = newDir.uri;
      }
    }

    final finalFile = await createDocumentFile(
      currentParentUri,
      fileName,
      isDirectory: false,
      initialContent: initialContent ?? '',
    );

    return (file: finalFile, createdDirs: createdDirs);
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
  String getParentUri(String uri) {
    final lastIndex = uri.lastIndexOf(_separator);
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
    final effectiveRelativeTo = relativeTo ?? rootUri;
    String path = uri;
    if (path.startsWith(effectiveRelativeTo)) {
      path = path.substring(effectiveRelativeTo.length);
      if (path.startsWith(_separator)) {
        path = path.substring(_separator.length);
      }
    }
    return path.split(_separator).map((s) => Uri.decodeComponent(s)).join('/');
  }

  @override
  String resolveRelativePath(String contextPath, String relativePath) {
    final contextDir = _pathContext.dirname(contextPath);

    final combined = _pathContext.join(contextDir, relativePath);
    return _pathContext.normalize(combined);
  }

  @override
  String calculateRelativePath(String fromContext, String toTarget) {
    final contextDir = _pathContext.dirname(fromContext);

    return _pathContext.relative(toTarget, from: contextDir);
  }
}
