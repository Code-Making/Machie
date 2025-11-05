// =========================================
// UPDATED: lib/explorer/plugins/git_explorer/git_file_content_provider.dart
// =========================================

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_git/dart_git.dart';

import '../../../data/dto/project_dto.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../editor/editor_tab_models.dart';
import '../../../editor/plugins/editor_plugin_models.dart';
import '../../../data/content_provider/file_content_provider.dart';
import 'git_object_file.dart';

// Imports from dart_git

// Imports from the machine app

/// Provides the content for virtual files that represent objects in the Git database.
class GitFileContentProvider implements FileContentProvider, IRehydratable {
  // It now holds its direct dependency instead of a Riverpod Ref.
  final GitRepository _gitRepo;

  GitFileContentProvider(this._gitRepo);

  @override
  Map<Type, String> get typeMappings => {GitObjectDocumentFile: 'git_object'};

  @override
  Future<EditorContentResult> getContent(
    DocumentFile file,
    PluginDataRequirement requirement,
  ) async {
    if (file is! GitObjectDocumentFile) {
      throw ArgumentError(
        'GitFileContentProvider can only handle GitObjectDocumentFile',
      );
    }

    // Use the injected dependency directly. All calls are now async.
    final blob = await _gitRepo.objStorage.readBlob(file.objectHash);
    final bytes = blob.blobData;

    final content =
        (requirement == PluginDataRequirement.bytes)
            ? EditorContentBytes(bytes)
            : EditorContentString(utf8.decode(bytes, allowMalformed: true));

    return EditorContentResult(
      content: content,
      baseContentHash: md5.convert(bytes).toString(),
    );
  }

  /// Saving is not supported for historical Git objects.
  /// Throws RequiresSaveAsException to prompt the user to save it as a new file.
  @override
  Future<SaveResult> saveContent(DocumentFile file, EditorContent content) {
    throw RequiresSaveAsException(file);
  }

  /// Rehydrating a historical Git file doesn't make sense as it's virtual and tied
  /// to a specific commit hash which isn't persisted in the tab metadata.
  /// We return null to indicate the tab for this file cannot be restored.
  @override
  Future<DocumentFile?> rehydrate(TabMetadataDto dto) {
    return Future.value(null);
  }
}
