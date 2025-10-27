// lib/explorer/plugins/git_explorer/git_file_content_provider.dart
import 'package:dart_git/git.dart'; // IMPORT dart_git
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/plugin_models.dart';
import 'package:machine/editor/services/file_content_provider.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/dto/project_dto.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'git_object_file.dart';
import 'package:dart_git/storage/object_storage_extensions.dart';

// UPDATED: This class is now pure and has no knowledge of Riverpod.
class GitFileContentProvider implements FileContentProvider, IRehydratable {
  // UPDATED: It now holds its direct dependency.
  final GitRepository _gitRepo;
  GitFileContentProvider(this._gitRepo);

  @override
  Map<Type, String> get typeMappings => {GitObjectDocumentFile: 'git_object'};

  @override
  Future<EditorContentResult> getContent(DocumentFile file, PluginDataRequirement requirement) async {
    if (file is! GitObjectDocumentFile) {
      throw ArgumentError('GitFileContentProvider can only handle GitObjectDocumentFile');
    }

    // UPDATED: Use the injected dependency directly.
    final blob = _gitRepo.objStorage.readBlob(file.objectHash);
    final bytes = blob.blobData;

    final content = (requirement == PluginDataRequirement.bytes)
        ? EditorContentBytes(bytes)
        : EditorContentString(utf8.decode(bytes, allowMalformed: true));

    return EditorContentResult(
      content: content,
      baseContentHash: md5.convert(bytes).toString(),
    );
  }
  
  // (saveContent and rehydrate are unchanged)
  @override
  Future<SaveResult> saveContent(DocumentFile file, EditorContent content) {
    throw RequiresSaveAsException(file);
  }

  @override
  Future<DocumentFile?> rehydrate(TabMetadataDto dto) {
    return Future.value(null);
  }
}