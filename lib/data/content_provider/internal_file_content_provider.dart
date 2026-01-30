import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../editor/models/editor_plugin_models.dart';
import '../../editor/models/editor_tab_models.dart';
import '../../project/project_models.dart';
import '../dto/project_dto.dart';
import '../file_handler/file_handler.dart';
import 'file_content_provider.dart';

class InternalFileContentProvider
    implements FileContentProvider, IRehydratable {
  static final Future<Directory> _appDocsDir =
      getApplicationDocumentsDirectory();

  @override
  Map<Type, String> get typeMappings => {InternalAppFile: 'internal_app_file'};

  Future<File> _getFileFromUri(String uri) async {
    final docsDir = await _appDocsDir;
    final fileName = uri.split(':
    return File('${docsDir.path}/$fileName');
  }

  @override
  Future<EditorContentResult> getContent(
    DocumentFile file,
    PluginDataRequirement requirement,
  ) async {
    final physicalFile = await _getFileFromUri(file.uri);
    String text = '';

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
      return InternalAppFile(
        uri: dto.fileUri,
        name: dto.fileName,
        modifiedDate: DateTime.now(),
      );
    }
  }
}
