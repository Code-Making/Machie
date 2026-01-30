import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor/models/editor_tab_models.dart';
import '../../editor/plugins/editor_plugin_registry.dart';
import '../../explorer/explorer_plugin_registry.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import '../file_handler/file_handler.dart';
import '../file_handler/local_file_handler_saf.dart';
import '../repositories/project/project_repository.dart';
import 'internal_file_content_provider.dart';

import '../dto/project_dto.dart';

/// A result class that encapsulates the content of a file and its MD5 hash.
class EditorContentResult {
  final EditorContent content;
  final String baseContentHash;

  EditorContentResult({required this.content, required this.baseContentHash});
}

/// A result class for a successful save operation.
class SaveResult {
  final DocumentFile savedFile;
  final String newContentHash;

  SaveResult({required this.savedFile, required this.newContentHash});
}

/// An exception to be thrown by a provider when it cannot save a file
/// directly and requires a "Save As" operation (e.g., for a new virtual file).
class RequiresSaveAsException implements Exception {
  final DocumentFile originalFile;
  const RequiresSaveAsException(this.originalFile);
  @override
  String toString() => 'This file must be saved using "Save As...".';
}

abstract class IRehydratable {
  /// Reconstructs the correct concrete DocumentFile instance from a DTO.
  Future<DocumentFile?> rehydrate(TabMetadataDto dto);
}

/// Abstract interface for a class that can provide and persist the content
/// associated with a [DocumentFile]. This decouples the EditorService from
/// the underlying storage mechanism (e.g., disk, memory, database).
// REFACTORED: The provider interface is simpler. No more priority or canHandle.
abstract class FileContentProvider {
  Map<Type, String> get typeMappings;


  Future<EditorContentResult> getContent(
    DocumentFile file,
    PluginDataRequirement requirement,
  );
  Future<SaveResult> saveContent(DocumentFile file, EditorContent content);
}

class ProjectFileContentProvider implements FileContentProvider, IRehydratable {
  final ProjectRepository _repo;
  ProjectFileContentProvider(this._repo);

  @override
  Map<Type, String> get typeMappings => {CustomSAFDocumentFile: 'project'};

  @override
  Future<EditorContentResult> getContent(
    DocumentFile file,
    PluginDataRequirement requirement,
  ) async {
    if (requirement == PluginDataRequirement.bytes) {
      final bytes = await _repo.readFileAsBytes(file.uri);
      return EditorContentResult(
        content: EditorContentBytes(bytes),
        baseContentHash: md5.convert(bytes).toString(),
      );
    } else {
      final text = await _repo.readFile(file.uri);
      final bytes = utf8.encode(text);
      return EditorContentResult(
        content: EditorContentString(text),
        baseContentHash: md5.convert(bytes).toString(),
      );
    }
  }

  @override
  Future<SaveResult> saveContent(
    DocumentFile file,
    EditorContent content,
  ) async {
    final projectFile = file as ProjectDocumentFile;
    if (content is EditorContentString) {
      final savedFile = await _repo.writeFile(projectFile, content.content);
      final hash = md5.convert(utf8.encode(content.content)).toString();
      return SaveResult(savedFile: savedFile, newContentHash: hash);
    } else if (content is EditorContentBytes) {
      final savedFile = await _repo.writeFileAsBytes(
        projectFile,
        content.bytes,
      );
      final hash = md5.convert(content.bytes).toString();
      return SaveResult(savedFile: savedFile, newContentHash: hash);
    }
    throw UnsupportedError('Unknown EditorContent type');
  }

  @override
  Future<DocumentFile?> rehydrate(TabMetadataDto dto) {
    return _repo.fileHandler.getFileMetadata(dto.fileUri);
  }
}

/// A provider specifically for handling in-memory [VirtualDocumentFile] instances.
class VirtualFileContentProvider implements FileContentProvider, IRehydratable {
  @override
  Map<Type, String> get typeMappings => {VirtualDocumentFile: 'virtual'};

  @override
  Future<EditorContentResult> getContent(
    DocumentFile file,
    PluginDataRequirement requirement,
  ) async {
    if (requirement == PluginDataRequirement.bytes) {
      final bytes = Uint8List(0);
      return EditorContentResult(
        content: EditorContentBytes(bytes),
        baseContentHash: md5.convert(bytes).toString(),
      );
    } else {
      final text = '';
      final bytes = utf8.encode(text);
      return EditorContentResult(
        content: EditorContentString(text),
        baseContentHash: md5.convert(bytes).toString(),
      );
    }
  }

  @override
  Future<SaveResult> saveContent(
    DocumentFile file,
    EditorContent content,
  ) async {
    throw RequiresSaveAsException(file);
  }

  @override
  Future<DocumentFile?> rehydrate(TabMetadataDto dto) {
    return Future.value(
      VirtualDocumentFile(uri: dto.fileUri, name: dto.fileName),
    );
  }
}

// --- Registry ---

/// Manages a collection of [FileContentProvider]s and selects the
/// appropriate one for a given file.
class FileContentProviderRegistry {
  final Map<Type, FileContentProvider> _providersByType;

  final Map<String, FileContentProvider> _providersById;

  final Map<Type, String> _typeIdentifiers;

  FileContentProviderRegistry(List<FileContentProvider> providers)
    : _providersByType = {},
      _providersById = {},
      _typeIdentifiers = {} {
    for (final provider in providers) {
      for (final entry in provider.typeMappings.entries) {
        final type = entry.key;
        final id = entry.value;

        if (_providersByType.containsKey(type)) {
        }
        _providersByType[type] = provider;

        if (_providersById.containsKey(id)) {
        }
        _providersById[id] = provider;

        _typeIdentifiers[type] = id;
      }
    }
  }

  FileContentProvider getProviderFor(DocumentFile file) {
    final provider = _providersByType[file.runtimeType];
    if (provider == null) {
      throw StateError(
        'No content provider registered for type: ${file.runtimeType}',
      );
    }
    return provider;
  }

  Future<DocumentFile?> rehydrateFileFromDto(TabMetadataDto dto) {
    final provider = _providersById[dto.fileType];

    if ((provider != null) && (provider is IRehydratable)) {
      return (provider as IRehydratable).rehydrate(dto);
    }

    return Future.value(null);
  }

  String getTypeIdForFile(DocumentFile file) {
    final typeId = _typeIdentifiers[file.runtimeType];
    if (typeId == null) {
      return 'unknown';
    }
    return typeId;
  }
}

// --- Riverpod Providers ---

final fileContentProviderRegistryProvider = Provider<
  FileContentProviderRegistry
>((ref) {
  final repo = ref.watch(projectRepositoryProvider);
  if (repo == null) return FileContentProviderRegistry([]);

  final allProviders = <FileContentProvider>[];

  final editorPluginFactories = ref
      .watch(activePluginsProvider)
      .expand((plugin) => plugin.fileContentProviderFactories);

  final explorerPluginFactories = ref
      .watch(explorerRegistryProvider)
      .expand((plugin) => plugin.fileContentProviderFactories);

  final allFactories = [...editorPluginFactories, ...explorerPluginFactories];

  for (final factory in allFactories) {
    try {
      final provider = factory(ref);
      allProviders.add(provider);
    } catch (e, st) {
      ref
          .read(talkerProvider)
          .handle(e, st, 'Failed to create a FileContentProvider via factory');
    }
  }

  final coreProviders = <FileContentProvider>[
    ProjectFileContentProvider(repo),
    VirtualFileContentProvider(),
    InternalFileContentProvider(),
  ];
  allProviders.addAll(coreProviders);

  return FileContentProviderRegistry(allProviders);
});
