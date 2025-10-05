// lib/project/services/project_hierarchy_service.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';

/// Represents a single node in the project's file tree.
class FileTreeNode {
  final DocumentFile file;
  FileTreeNode(this.file);
}

/// A service that manages the project's file hierarchy using a hybrid approach:
/// 1. On-demand lazy-loading for responsive UI browsing.
/// 2. A concurrent, non-blocking full background scan for search indexing.
class ProjectHierarchyService extends Notifier<Map<String, AsyncValue<List<FileTreeNode>>>> {
  ProviderSubscription? _projectSubscription;
  ProviderSubscription? _fileOpSubscription;

  @override
  Map<String, AsyncValue<List<FileTreeNode>>> build() {
    _projectSubscription = ref.listen<Project?>(
      appNotifierProvider.select((s) => s.value?.currentProject),
      (previous, next) {
        _fileOpSubscription?.close();
        if (next != null) {
          state = {};
          _initializeHierarchy(next);
          _listenForFileChanges();
        } else {
          state = {};
        }
      },
      fireImmediately: true,
    );

    ref.onDispose(() {
      _projectSubscription?.close();
      _fileOpSubscription?.close();
    });

    return {};
  }

  /// Kicks off the entire loading process for a new project.
  Future<void> _initializeHierarchy(Project project) async {
    // First, load the root directory to make the UI immediately responsive.
    final rootNodes = await loadDirectory(project.rootUri);
    // Once the root is successfully loaded, start the non-blocking full scan.
    if (rootNodes != null) {
      _startFullBackgroundScan(project);
    }
  }

  /// Public method to trigger a lazy-load for a specific directory.
  /// Returns the loaded nodes, or null if an error occurred.
  Future<List<FileTreeNode>?> loadDirectory(String uri) async {
    // If directory is already loaded or is currently loading, do nothing.
    if (state[uri] is AsyncLoading || state[uri] is AsyncData) {
      return state[uri]?.value;
    }

    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return null;
    
    // FIX: Update state correctly without reading from the provider.
    state = {...state, uri: const AsyncLoading()};

    try {
      final items = await repo.listDirectory(uri);
      final nodes = items.map((file) => FileTreeNode(file)).toList();
      state = {...state, uri: AsyncData(nodes)};
      return nodes;
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Failed to load directory: $uri');
      state = {...state, uri: AsyncError(e, st)};
      return null;
    }
  }
  
  /// Kicks off a non-blocking, breadth-first scan of the entire project tree.
  void _startFullBackgroundScan(Project project) {
    // This runs as a fire-and-forget async task.
    unawaited(Future(() async {
      final talker = ref.read(talkerProvider);
      talker.info('[ProjectHierarchyService] Starting full background scan...');
      
      // FIX: Use a standard while loop which works with a dynamic queue.
      final queue = <String>[project.rootUri];
      final Set<String> processedUris = {project.rootUri};

      while (queue.isNotEmpty) {
        // Ensure the project hasn't been closed during the scan.
        if (ref.read(appNotifierProvider).value?.currentProject?.id != project.id) {
          talker.info('[ProjectHierarchyService] Project changed, abandoning background scan.');
          return;
        }

        final currentUri = queue.removeAt(0);
        
        // This directory might have already been loaded by the user.
        final existingData = state[currentUri]?.valueOrNull;
        final List<FileTreeNode> children;

        if (existingData != null) {
          children = existingData;
        } else {
          // If not, load it now as part of the scan.
          children = await loadDirectory(currentUri) ?? [];
        }
        
        for (final childNode in children) {
          if (childNode.file.isDirectory && !processedUris.contains(childNode.file.uri)) {
            queue.add(childNode.file.uri);
            processedUris.add(childNode.file.uri);
          }
        }

        // FIX: Yield to the event loop to prevent freezing the UI on large projects.
        await Future.delayed(Duration.zero);
      }
      talker.info('[ProjectHierarchyService] Full background scan complete.');
    }));
  }

  void _listenForFileChanges() {
    _fileOpSubscription = ref.listen<AsyncValue<FileOperationEvent>>(
      fileOperationStreamProvider,
      (previous, next) {
        next.whenData((event) {
          final repo = ref.read(projectRepositoryProvider);
          if (repo == null) return;
          
          switch (event) {
            case FileCreateEvent(createdFile: final file):
              final parentUri = repo.fileHandler.getParentUri(file.uri);
              final parentState = state[parentUri];
              if (parentState is AsyncData) {
                final parentContents = parentState.value;
                if (!parentContents.any((node) => node.file.uri == file.uri)) {
                   state = {...state, parentUri: AsyncData([...parentContents, FileTreeNode(file)])};
                }
              }
              break;

            case FileDeleteEvent(deletedFile: final file):
              final parentUri = repo.fileHandler.getParentUri(file.uri);
              final parentState = state[parentUri];
              if (parentState is AsyncData) {
                final parentContents = parentState.value;
                state = {...state, parentUri: AsyncData(parentContents.where((node) => node.file.uri != file.uri).toList())};
              }
              if (file.isDirectory) {
                state = Map.from(state)..remove(file.uri);
              }
              break;
              
            case FileRenameEvent():
              final project = ref.read(appNotifierProvider).value!.currentProject;
              if (project != null) {
                 _initializeHierarchy(project);
              }
              break;
          }
        });
      },
    );
  }
}

// --- Providers ---

final projectHierarchyServiceProvider = NotifierProvider<ProjectHierarchyService, Map<String, AsyncValue<List<FileTreeNode>>>>(
  ProjectHierarchyService.new,
);

final flatFileIndexProvider = Provider.autoDispose<AsyncValue<List<DocumentFile>>>((ref) {
  final hierarchyState = ref.watch(projectHierarchyServiceProvider);
  final allFiles = <DocumentFile>[];
  
  // FIX: This now correctly handles AsyncValue and avoids adding duplicates.
  final addedUris = <String>{};
  for (final entry in hierarchyState.entries) {
    entry.value.whenData((nodes) {
      for (final node in nodes) {
        if (!node.file.isDirectory && !addedUris.contains(node.file.uri)) {
          allFiles.add(node.file);
          addedUris.add(node.file.uri);
        }
      }
    });
  }
  return AsyncData(allFiles);
});

final directoryContentsProvider = Provider.family.autoDispose<AsyncValue<List<FileTreeNode>>?, String>((ref, directoryUri) {
  final hierarchyState = ref.watch(projectHierarchyServiceProvider);
  return hierarchyState[directoryUri];
});