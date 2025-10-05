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
  final FileTreeNode? parent;
  final List<FileTreeNode> children = [];

  FileTreeNode(this.file, {this.parent});

  /// Helper to find a descendant node by its URI path.
  FileTreeNode? findNodeByUri(String uri) {
    if (file.uri == uri) {
      return this;
    }
    for (final child in children) {
      final found = child.findNodeByUri(uri);
      if (found != null) {
        return found;
      }
    }
    return null;
  }
}

/// A service that builds and maintains a complete in-memory tree of the
/// project's file hierarchy. This is the single source of truth for all
/// file-related UI components.
class ProjectHierarchyService extends Notifier<AsyncValue<FileTreeNode?>> {
  StreamSubscription? _fileOpSubscription;

  @override
  AsyncValue<FileTreeNode?> build() {
    // Rebuild the hierarchy whenever the current project changes.
    ref.listen<Project?>(
      appNotifierProvider.select((s) => s.value?.currentProject),
      (previous, next) {
        _fileOpSubscription?.cancel();
        if (next != null) {
          _buildHierarchy(next);
          _listenForFileChanges();
        } else {
          state = const AsyncValue.data(null); // No project open
        }
      },
      fireImmediately: true,
    );

    // Initial state before the listener fires
    return const AsyncValue.data(null);
  }

  /// Performs the initial, recursive scan of the project directory to build the tree.
  Future<void> _buildHierarchy(Project project) async {
    state = const AsyncValue.loading();
    final repo = ref.read(projectRepositoryProvider);
    final talker = ref.read(talkerProvider);

    if (repo == null) {
      state = AsyncValue.error('Project is not open.', StackTrace.current);
      return;
    }

    talker.info('[ProjectHierarchyService] Building file tree...');
    try {
      final rootFile = VirtualDocumentFile(uri: project.rootUri, name: project.name, isDirectory: true);
      final rootNode = FileTreeNode(rootFile);
      
      final directoriesToScan = [rootNode];
      while (directoriesToScan.isNotEmpty) {
        final currentNode = directoriesToScan.removeAt(0);
        final items = await repo.listDirectory(currentNode.file.uri);
        for (final item in items) {
          final childNode = FileTreeNode(item, parent: currentNode);
          currentNode.children.add(childNode);
          if (item.isDirectory) {
            directoriesToScan.add(childNode);
          }
        }
      }
      talker.info('[ProjectHierarchyService] File tree built successfully.');
      if (mounted) {
        state = AsyncValue.data(rootNode);
      }
    } catch (e, st) {
      talker.handle(e, st, '[ProjectHierarchyService] Failed to build file tree.');
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// Subscribes to file operations to keep the tree in sync without a full rebuild.
  void _listenForFileChanges() {
    _fileOpSubscription = ref.listen<AsyncValue<FileOperationEvent>>(
      fileOperationStreamProvider,
      (previous, next) {
        next.whenData((event) {
          if (state.value == null) return;
          final rootNode = state.value!;
          
          switch (event) {
            case FileCreateEvent(createdFile: final file):
              final parentUri = ref.read(projectRepositoryProvider)!.fileHandler.getParentUri(file.uri);
              final parentNode = rootNode.findNodeByUri(parentUri);
              if (parentNode != null) {
                // Avoid adding duplicates if event fires multiple times
                if (!parentNode.children.any((node) => node.file.uri == file.uri)) {
                  parentNode.children.add(FileTreeNode(file, parent: parentNode));
                  state = AsyncValue.data(rootNode); 
                }
              }
              break;

            case FileDeleteEvent(deletedFile: final file):
              final parentUri = ref.read(projectRepositoryProvider)!.fileHandler.getParentUri(file.uri);
              final parentNode = rootNode.findNodeByUri(parentUri);
              if (parentNode != null) {
                parentNode.children.removeWhere((node) => node.file.uri == file.uri);
                state = AsyncValue.data(rootNode);
              }
              break;
              
            case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
              // Renaming a folder invalidates all children URIs, so a full rebuild is safest.
              if (newFile.isDirectory) {
                 final project = ref.read(appNotifierProvider).value!.currentProject!;
                _buildHierarchy(project);
              } else {
                 final parentUri = ref.read(projectRepositoryProvider)!.fileHandler.getParentUri(newFile.uri);
                 final parentNode = rootNode.findNodeByUri(parentUri);
                 if (parentNode != null) {
                    parentNode.children.removeWhere((n) => n.file.uri == oldFile.uri);
                    parentNode.children.add(FileTreeNode(newFile, parent: parentNode));
                    state = AsyncValue.data(rootNode);
                 }
              }
              break;
          }
        });
      },
    );
  }
}

// --- Providers ---

final projectHierarchyServiceProvider = NotifierProvider<ProjectHierarchyService, AsyncValue<FileTreeNode?>>(
  ProjectHierarchyService.new,
);

/// A derived provider that returns a flat list of all files (not directories) in the project.
/// Ideal for the search feature. This is an instantaneous memory operation.
final flatFileIndexProvider = Provider<AsyncValue<List<DocumentFile>>>((ref) {
  return ref.watch(projectHierarchyServiceProvider).when(
    data: (rootNode) {
      if (rootNode == null) return const AsyncValue.data([]);
      final allFiles = <DocumentFile>[];
      final nodesToVisit = [rootNode];
      while(nodesToVisit.isNotEmpty) {
        final node = nodesToVisit.removeAt(0);
        if (!node.file.isDirectory) {
          allFiles.add(node.file);
        }
        nodesToVisit.addAll(node.children);
      }
      return AsyncValue.data(allFiles);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

/// A derived provider that returns the immediate children of a given directory URI.
/// Ideal for the file explorer view. This is an instantaneous memory operation.
final directoryContentsProvider = Provider.family<List<FileTreeNode>?, String>((ref, directoryUri) {
  final rootNodeAsync = ref.watch(projectHierarchyServiceProvider);
  
  return rootNodeAsync.when(
    data: (rootNode) {
      if (rootNode == null) return null;
      return rootNode.findNodeByUri(directoryUri)?.children;
    },
    loading: () => null, // Return null to indicate loading
    error: (_, __) => [], // Return empty list on error
  );
});