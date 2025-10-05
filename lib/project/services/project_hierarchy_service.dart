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
          // Reset state and kick off the hybrid loading process
          state = {};
          loadDirectory(next.rootUri); // Immediate load for root UI
          _startFullBackgroundScan(next); // Non-blocking full scan
          _listenForFileChanges();
        } else {
          state = {}; // No project open
        }
      },
      fireImmediately: true,
    );

    ref.onDispose(() {
      _projectSubscription?.close();
      _fileOpSubscription?.close();
    });

    return {}; // Initial state is an empty map
  }

  /// Public method to trigger a lazy-load for a specific directory.
  /// This is called by the UI when a folder is expanded.
  Future<void> loadDirectory(String uri) async {
    // If directory is already loaded or is currently loading, do nothing.
    if (state.containsKey(uri)) {
      return;
    }

    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;
    
    // Set state to loading for this specific directory
    state = {...state, uri: const AsyncLoading()};

    try {
      final items = await repo.listDirectory(uri);
      final nodes = items.map((file) => FileTreeNode(file)).toList();
      state = {...state, uri: AsyncData(nodes)};
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Failed to load directory: $uri');
      state = {...state, uri: AsyncError(e, st)};
    }
  }
  
  /// Kicks off a non-blocking, breadth-first scan of the entire project tree.
  void _startFullBackgroundScan(Project project) async {
    final talker = ref.read(talkerProvider);
    talker.info('[ProjectHierarchyService] Starting full background scan...');
    
    final queue = <String>[project.rootUri];
    final Set<String> scannedUris = {project.rootUri};

    // Process the queue asynchronously without blocking the UI
    await for (final uri in Stream.fromIterable(queue)) {
      // Ensure the project hasn't been closed during the scan
      if (ref.read(appNotifierProvider).value?.currentProject?.id != project.id) {
        talker.info('[ProjectHierarchyService] Project changed, abandoning background scan.');
        return;
      }

      // Check if we already have the data (loaded by user or a previous scan iteration)
      final currentState = state[uri];
      List<FileTreeNode> children;
      if (currentState is AsyncData<List<FileTreeNode>>) {
        children = currentState.value;
      } else {
        // If not loaded, fetch it now.
        await loadDirectory(uri);
        children = state[uri]?.valueOrNull ?? [];
      }
      
      // Add newly discovered subdirectories to the queue for the next iteration
      for (final childNode in children) {
        if (childNode.file.isDirectory && !scannedUris.contains(childNode.file.uri)) {
          queue.add(childNode.file.uri);
          scannedUris.add(childNode.file.uri);
        }
      }
    }
    talker.info('[ProjectHierarchyService] Full background scan complete.');
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
              if (state[parentUri] is AsyncData) {
                final parentContents = state[parentUri]!.value!;
                if (!parentContents.any((node) => node.file.uri == file.uri)) {
                   state = {...state, parentUri: AsyncData([...parentContents, FileTreeNode(file)])};
                }
              }
              break;

            case FileDeleteEvent(deletedFile: final file):
              final parentUri = repo.fileHandler.getParentUri(file.uri);
              if (state[parentUri] is AsyncData) {
                final parentContents = state[parentUri]!.value!;
                state = {...state, parentUri: AsyncData(parentContents.where((node) => node.file.uri != file.uri).toList())};
              }
              // If it was a directory, remove its own entry from the state map
              if (file.isDirectory) {
                state = Map.from(state)..remove(file.uri);
              }
              break;
              
            case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
              // Renaming is complex. The safest and simplest approach is to invalidate
              // the parent and the (potentially old) directory itself.
              final parentUri = repo.fileHandler.getParentUri(newFile.uri);
              state = Map.from(state)..remove(parentUri);
              if (oldFile.isDirectory) {
                state = Map.from(state)..remove(oldFile.uri);
              }
              // Trigger a reload for the parent to show the renamed item
              loadDirectory(parentUri);
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

/// A derived provider that returns a flat list of all files (not directories) in the project.
/// This will become populated as the background scan runs.
final flatFileIndexProvider = Provider<AsyncValue<List<DocumentFile>>>((ref) {
  final hierarchyState = ref.watch(projectHierarchyServiceProvider);
  final allFiles = <DocumentFile>[];
  
  for (final entry in hierarchyState.entries) {
    if (entry.value is AsyncData<List<FileTreeNode>>) {
      for (final node in entry.value.value!) {
        if (!node.file.isDirectory) {
          allFiles.add(node.file);
        }
      }
    }
  }
  return AsyncData(allFiles);
});

/// A derived provider that returns the loading state and contents of a single directory.
final directoryContentsProvider = Provider.family<AsyncValue<List<FileTreeNode>>?, String>((ref, directoryUri) {
  final hierarchyState = ref.watch(projectHierarchyServiceProvider);
  return hierarchyState[directoryUri];
});