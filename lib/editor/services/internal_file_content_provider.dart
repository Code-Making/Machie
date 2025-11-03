// =========================================
// NEW FILE: lib/editor/services/internal_file_content_provider.dart
// =========================================

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/dto/project_dto.dart';
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import '../editor_tab_models.dart';
import '../plugins/plugin_models.dart';
import 'file_content_provider.dart';

class InternalFileContentProvider
    implements FileContentProvider, IRehydratable {
  // Use a singleton future to avoid calling getApplicationDocumentsDirectory repeatedly.
  static final Future<Directory> _appDocsDir =
      getApplicationDocumentsDirectory();

  @override
  Map<Type, String> get typeMappings => {InternalAppFile: 'internal_app_file'};

  /// Converts an "internal://" URI to a full file system path.
  Future<File> _getFileFromUri(String uri) async {
    final docsDir = await _appDocsDir;
    // Assumes URI is like "internal://<filename>"
    final fileName = uri.split('://').last;
    return File('${docsDir.path}/$fileName');
  }

  @override
  Future<EditorContentResult> getContent(
    DocumentFile file,
    PluginDataRequirement requirement,
  ) async {
    final physicalFile = await _getFileFromUri(file.uri);
    String text = '';

    // If the file exists, read it. Otherwise, return empty content.
    if (await physicalFile.exists()) {
      text = await physicalFile.readAsString();
    }

    final bytes = utf8.encode(text);
    return EditorContentResult(
      content: EditorContentString(text),
      baseContentHash: md5.convert(bytes).toString(),
    );
  }

  @override
  Future<SaveResult> saveContent(
    DocumentFile file,
    EditorContent content,
  ) async {
    if (content is! EditorContentString) {
      throw UnsupportedError(
        'Internal files currently only support text content.',
      );
    }

    final physicalFile = await _getFileFromUri(file.uri);
    await physicalFile.writeAsString(content.content);

    final newHash = md5.convert(utf8.encode(content.content)).toString();
    final stats = await physicalFile.stat();

    // Return a new InternalAppFile with updated metadata.
    final savedFile = InternalAppFile(
      uri: file.uri,
      name: file.name,
      size: stats.size,
      modifiedDate: stats.modified,
    );

    return SaveResult(savedFile: savedFile, newContentHash: newHash);
  }

  @override
  Future<DocumentFile?> rehydrate(TabMetadataDto dto) async {
    // Rehydration involves checking if the file actually exists on disk
    // to get its current metadata.
    final physicalFile = await _getFileFromUri(dto.fileUri);
    if (await physicalFile.exists()) {
      final stats = await physicalFile.stat();
      return InternalAppFile(
        uri: dto.fileUri,
        name: dto.fileName,
        size: stats.size,
        modifiedDate: stats.modified,
      );
    } else {
      // If the file doesn't exist (e.g., first run), create a placeholder.
      return InternalAppFile(
        uri: dto.fileUri,
        name: dto.fileName,
        modifiedDate: DateTime.now(),
      );
    }
  }
}
