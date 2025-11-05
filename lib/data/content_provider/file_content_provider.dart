// =========================================
// NEW FILE: lib/editor/services/file_content_provider.dart
// =========================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../file_handler/file_handler.dart';
import '../file_handler/local_file_handler_saf.dart';
import '../repositories/project/project_repository.dart';
import '../../editor/editor_tab_models.dart';
import '../../explorer/explorer_plugin_registry.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import '../../editor/plugins/editor_plugin_registry.dart';
import 'internal_file_content_provider.dart';

import '../dto/project_dto.dart'; // NEW IMPORT

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
  // REFACTORED: This is the core change. The provider now declares an
  // explicit mapping from each concrete file Type to its stable serialization String ID.
  /// A map where the key is a concrete [DocumentFile] `Type` and the value
  /// is its unique, stable string identifier for serialization.
  Map<Type, String> get typeMappings;

  // REMOVED: `handledTypes` and `typeId` are now obsolete.

  Future<EditorContentResult> getContent(
    DocumentFile file,
    PluginDataRequirement requirement,
  );
  Future<SaveResult> saveContent(DocumentFile file, EditorContent content);
}

// REFACTORED: This provider now specifically handles ProjectDocumentFile types.
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
    // We can safely cast here because the registry guarantees this provider
    // only receives ProjectDocumentFile types.
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
    // For project files, we query the file system to get the live,
    // up-to-date metadata.
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
    // A new virtual file is always empty.
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
    // A virtual file cannot be saved directly. It must go through the "Save As" flow.
    // Throwing this specific exception allows the EditorService to catch it and
    // orchestrate the correct UI flow.
    throw RequiresSaveAsException(file);
  }

  @override
  Future<DocumentFile?> rehydrate(TabMetadataDto dto) {
    // For virtual files, we reconstruct it directly from the DTO's data.
    // This is an asynchronous future to match the interface, but completes immediately.
    return Future.value(
      VirtualDocumentFile(uri: dto.fileUri, name: dto.fileName),
    );
  }
}

// --- Registry ---

/// Manages a collection of [FileContentProvider]s and selects the
/// appropriate one for a given file.
class FileContentProviderRegistry {
  /// For runtime lookups: `Map<ConcreteType, ProviderInstance>`
  final Map<Type, FileContentProvider> _providersByType;

  /// For rehydration from DTO: `Map<StringId, ProviderInstance>`
  final Map<String, FileContentProvider> _providersById;

  /// For serialization to DTO: `Map<ConcreteType, StringId>`
  final Map<Type, String> _typeIdentifiers;

  /// The constructor takes a flat list of providers and intelligently builds
  /// the internal lookup maps from the self-describing `typeMappings`.
  FileContentProviderRegistry(List<FileContentProvider> providers)
    : _providersByType = {},
      _providersById = {},
      _typeIdentifiers = {} {
    for (final provider in providers) {
      // Iterate through the explicit mappings provided by each provider.
      for (final entry in provider.typeMappings.entries) {
        final type = entry.key;
        final id = entry.value;

        // 1. Build the runtime lookup map (Type -> Provider)
        if (_providersByType.containsKey(type)) {
          // print('Warning: Overwriting FileContentProvider for type $type.');
        }
        _providersByType[type] = provider;

        // 2. Build the rehydration lookup map (String ID -> Provider)
        if (_providersById.containsKey(id)) {
          // print('Warning: Overwriting FileContentProvider for typeId "$id".');
        }
        _providersById[id] = provider;

        // 3. Build the serialization lookup map (Type -> String ID)
        _typeIdentifiers[type] = id;
      }
    }
  }

  /// Selects the correct provider for a given [DocumentFile] instance at runtime.
  FileContentProvider getProviderFor(DocumentFile file) {
    final provider = _providersByType[file.runtimeType];
    if (provider == null) {
      throw StateError(
        'No content provider registered for type: ${file.runtimeType}',
      );
    }
    return provider;
  }

  /// Reconstructs a concrete [DocumentFile] from a DTO by finding the correct
  /// provider based on the serialized type ID.
  Future<DocumentFile?> rehydrateFileFromDto(TabMetadataDto dto) {
    final provider = _providersById[dto.fileType];

    if ((provider != null) && (provider is IRehydratable)) {
      return (provider as IRehydratable).rehydrate(dto);
    }

    // print(
    //   'Warning: No IRehydratable provider found for fileType "${dto.fileType}". Cannot rehydrate file.',
    // );
    return Future.value(null);
  }

  /// Gets the stable string identifier for a given [DocumentFile] instance,
  /// used for serialization.
  String getTypeIdForFile(DocumentFile file) {
    final typeId = _typeIdentifiers[file.runtimeType];
    if (typeId == null) {
      // print(
      //   'Warning: No type identifier found for file type ${file.runtimeType}.',
      // );
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

  // 1. Get all factories from EDITOR plugins.
  final editorPluginFactories = ref
      .watch(activePluginsProvider)
      .expand((plugin) => plugin.fileContentProviderFactories);

  // 2. Get all factories from EXPLORER plugins.
  final explorerPluginFactories = ref
      .watch(explorerRegistryProvider)
      .expand((plugin) => plugin.fileContentProviderFactories);

  // 3. Combine them all into a single list of factories.
  final allFactories = [...editorPluginFactories, ...explorerPluginFactories];

  // 4. Execute each factory to build the provider instances.
  for (final factory in allFactories) {
    try {
      // The factory is called here, with the ref it needs to resolve dependencies.
      final provider = factory(ref);
      allProviders.add(provider);
    } catch (e, st) {
      // If a factory fails (e.g., git repo not found), we can safely ignore it.
      // That provider simply won't be available.
      ref
          .read(talkerProvider)
          .handle(e, st, 'Failed to create a FileContentProvider via factory');
    }
  }

  // 5. Add the core, default providers.
  final coreProviders = <FileContentProvider>[
    ProjectFileContentProvider(repo),
    VirtualFileContentProvider(),
    InternalFileContentProvider(),
  ];
  allProviders.addAll(coreProviders);

  return FileContentProviderRegistry(allProviders);
});
