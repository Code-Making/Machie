// lib/explorer/plugins/git_explorer/git_file_content_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/plugin_models.dart';
import 'package:machine/editor/services/file_content_provider.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/dto/project_dto.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'git_object_file.dart';
import 'git_provider.dart';

class GitFileContentProvider implements FileContentProvider, IRehydratable {
  final Ref _ref;
  GitFileContentProvider(this._ref);

  @override
  Map<Type, String> get typeMappings => {GitObjectDocumentFile: 'git_object'};

  @override
  Future<EditorContentResult> getContent(DocumentFile file, PluginDataRequirement requirement) async {
    if (file is! GitObjectDocumentFile) {
      throw ArgumentError('GitFileContentProvider can only handle GitObjectDocumentFile');
    }

    final gitRepo = _ref.read(gitRepositoryProvider);
    if (gitRepo == null) {
      throw Exception('Git repository not available');
    }

    // Read the blob content from the git object store
    final blob = gitRepo.objStorage.readBlob(file.objectHash);
    final bytes = blob.blobData;

    final content = (requirement == PluginDataRequirement.bytes)
        ? EditorContentBytes(bytes)
        : EditorContentString(utf8.decode(bytes, allowMalformed: true));

    return EditorContentResult(
      content: content,
      baseContentHash: md5.convert(bytes).toString(),
    );
  }

  @override
  Future<SaveResult> saveContent(DocumentFile file, EditorContent content) {
    // These files are historical and read-only.
    throw RequiresSaveAsException(file);
  }

  @override
  Future<DocumentFile?> rehydrate(TabMetadataDto dto) {
    // Cannot rehydrate a virtual git file as it requires a live git repo context.
    // The app logic should prevent these tabs from being persisted.
    return Future.value(null);
  }
}