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
    // Once the root is loaded, start the non-blocking full scan in the background.
    if (rootNodes != null) {
      _startFullBackgroundScan(project, rootNodes);
    }
  }

  /// Public method to trigger a lazy-load for a specific directory.
  /// Returns the loaded nodes, or null if an error occurred.
  Future<List<FileTreeNode>?> loadDirectory(String uri) async {
    if (state[uri] is AsyncLoading) return null; // Already loading

    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return null;
    
    state = {...state, uri: const AsyncLoading()};

    try {
      final items = await repo.listDirectory(uri);
      final nodes = items.map((file) => FileTreeNode(file)).toList();
      
      // FIX: Read the latest state map before updating to prevent race conditions.
      final currentState = ref.read(projectHierarchyServiceProvider);
      state = {...currentState, uri: AsyncData(nodes)};
      return nodes;
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Failed to load directory: $uri');
      final currentState = ref.read(projectHierarchyServiceProvider);
      state = {...currentState, uri: AsyncError(e, st)};
      return null;
    }
  }
  
  /// Kicks off a non-blocking, breadth-first scan of the entire project tree.
  void _startFullBackgroundScan(Project project, List<FileTreeNode> rootNodes) {
    // Use an unscoped provider to avoid it being disposed if no UI is listening
    final container = ProviderContainer();
    
    // This runs as a fire-and-forget async task.
    unawaited(Future(() async {
      final talker = container.read(talkerProvider);
      talker.info('[ProjectHierarchyService] Starting full background scan...');
      
      // FIX: Use a standard while loop which works with a dynamic queue.
      final queue = rootNodes
          .where((node) => node.file.isDirectory)
          .map((node) => node.file.uri)
          .toList();
      final Set<String> scannedUris = Set.from(queue)..add(project.rootUri);

      while (queue.isNotEmpty) {
        // Ensure the project hasn't been closed during the scan
        if (container.read(appNotifierProvider).value?.currentProject?.id != project.id) {
          talker.info('[ProjectHierarchyService] Project changed, abandoning background scan.');
          container.dispose();
          return;
        }

        final currentUri = queue.removeAt(0);
        
        // If the directory hasn't been loaded by user interaction yet, load it now.
        if (ref.read(projectHierarchyServiceProvider)[currentUri] == null) {
          final children = await loadDirectory(currentUri);
          if (children != null) {
            for (final childNode in children) {
              if (childNode.file.isDirectory && !scannedUris.contains(childNode.file.uri)) {
                queue.add(childNode.file.uri);
                scannedUris.add(childNode.file.uri);
              }
            }
          }
        }
      }
      talker.info('[ProjectHierarchyService] Full background scan complete.');
      container.dispose();
    }));
  }

  void _listenForFileChanges() {
    _fileOpSubscription = ref.listen<AsyncValue<FileOperationEvent>>(
      fileOperationStreamProvider,
      (previous, next) {
        next.whenData((event) {
          final repo = ref.read(projectRepositoryProvider);
          if (repo == null) return;
          
          final currentState = ref.read(projectHierarchyServiceProvider);
          Map<String, AsyncValue<List<FileTreeNode>>> newState = Map.from(currentState);

          switch (event) {
            case FileCreateEvent(createdFile: final file):
              final parentUri = repo.fileHandler.getParentUri(file.uri);
              if (newState[parentUri] is AsyncData) {
                final parentContents = newState[parentUri]!.value!;
                if (!parentContents.any((node) => node.file.uri == file.uri)) {
                   newState[parentUri] = AsyncData([...parentContents, FileTreeNode(file)]);
                }
              }
              break;

            case FileDeleteEvent(deletedFile: final file):
              final parentUri = repo.fileHandler.getParentUri(file.uri);
              if (newState[parentUri] is AsyncData) {
                final parentContents = newState[parentUri]!.value!;
                newState[parentUri] = AsyncData(parentContents.where((node) => node.file.uri != file.uri).toList());
              }
              if (file.isDirectory) {
                newState.remove(file.uri);
              }
              break;
              
            case FileRenameEvent():
              // Renaming is complex. A full invalidation is the simplest, most robust solution.
              // It will trigger a fresh hybrid load.
              final project = ref.read(appNotifierProvider).value!.currentProject;
              if (project != null) {
                 _initializeHierarchy(project);
              }
              return; // Exit early as state is being rebuilt
          }
          state = newState;
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
  
  // This can be slow on very large projects. Could be optimized further if needed.
  for (final entry in hierarchyState.entries) {
    entry.value.whenData((nodes) {
      for (final node in nodes) {
        if (!node.file.isDirectory) {
          allFiles.add(node.file);
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