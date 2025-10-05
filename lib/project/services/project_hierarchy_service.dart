// lib/project/services/project_hierarchy_service.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';

// (FileTreeNode class remains the same)
class FileTreeNode {
  final DocumentFile file;
  FileTreeNode(this.file);
}

class ProjectHierarchyService extends Notifier<Map<String, AsyncValue<List<FileTreeNode>>>> {
  // REMOVED: These member variables are no longer needed.
  // ProviderSubscription? _projectSubscription;
  // ProviderSubscription? _fileOpSubscription;

  @override
  Map<String, AsyncValue<List<FileTreeNode>>> build() {
    // By calling ref.listen here, Riverpod manages the subscription's lifecycle.
    // It will be automatically closed when this provider is disposed.
    ref.listen<Project?>(
      appNotifierProvider.select((s) => s.value?.currentProject),
      (previous, next) {
        // We still need to clean up the file op listener when the project changes.
        // But we don't need a member variable for it. We can just re-listen.
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

    // REMOVED: The ref.onDispose block for closing subscriptions is gone.
    // Riverpod handles this automatically for listeners created in `build`.

    return {};
  }

  // (The rest of the class logic is identical, as it was already correct)

  Future<void> _initializeHierarchy(Project project) async {
    final rootNodes = await loadDirectory(project.rootUri);
    if (rootNodes != null) {
      _startFullBackgroundScan(project);
    }
  }

  Future<List<FileTreeNode>?> loadDirectory(String uri) async {
    if (state[uri] is AsyncLoading || state[uri] is AsyncData) {
      return state[uri]?.value;
    }
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return null;
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
  
  void _startFullBackgroundScan(Project project) {
    unawaited(Future(() async {
      final talker = ref.read(talkerProvider);
      talker.info('[ProjectHierarchyService] Starting full background scan...');
      final queue = <String>[project.rootUri];
      final Set<String> processedUris = {project.rootUri};
      while (queue.isNotEmpty) {
        if (ref.read(appNotifierProvider).value?.currentProject?.id != project.id) {
          talker.info('[ProjectHierarchyService] Project changed, abandoning background scan.');
          return;
        }
        final currentUri = queue.removeAt(0);
        final existingData = state[currentUri]?.valueOrNull;
        final List<FileTreeNode> children;
        if (existingData != null) {
          children = existingData;
        } else {
          children = await loadDirectory(currentUri) ?? [];
        }
        for (final childNode in children) {
          if (childNode.file.isDirectory && !processedUris.contains(childNode.file.uri)) {
            queue.add(childNode.file.uri);
            processedUris.add(childNode.file.uri);
          }
        }
        await Future.delayed(Duration.zero);
      }
      talker.info('[ProjectHierarchyService] Full background scan complete.');
    }));
  }

  void _listenForFileChanges() {
    // This listener is now also automatically managed by Riverpod.
    // We don't need to store its subscription.
    ref.listen<AsyncValue<FileOperationEvent>>(
      fileOperationStreamProvider,
      (previous, next) {
        next.whenData((event) {
          final repo = ref.read(projectRepositoryProvider);
          if (repo == null) return;
          switch (event) {
            case FileCreateEvent(createdFile: final file):
              final parentUri = repo.fileHandler.getParentUri(file.uri);
              final parentAsyncValue = state[parentUri];
              if (parentAsyncValue is AsyncData<List<FileTreeNode>>) {
                final parentContents = parentAsyncValue.value;
                if (!parentContents.any((node) => node.file.uri == file.uri)) {
                   state = {...state, parentUri: AsyncData([...parentContents, FileTreeNode(file)])};
                }
              }
              break;
            case FileDeleteEvent(deletedFile: final file):
              final parentUri = repo.fileHandler.getParentUri(file.uri);
              final parentAsyncValue = state[parentUri];
              if (parentAsyncValue is AsyncData<List<FileTreeNode>>) {
                final parentContents = parentAsyncValue.value;
                state = {...state, parentUri: AsyncData(parentContents.where((node) => node.file.uri != file.uri).toList())};
              }
              if (file.isDirectory) {
                if (state.containsKey(file.uri)) {
                  final newState = Map<String, AsyncValue<List<FileTreeNode>>>.from(state)..remove(file.uri);
                  state = newState;
                }
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
// (These remain unchanged)

final projectHierarchyServiceProvider = NotifierProvider<ProjectHierarchyService, Map<String, AsyncValue<List<FileTreeNode>>>>(
  ProjectHierarchyService.new,
);

final flatFileIndexProvider = Provider.autoDispose<AsyncValue<List<DocumentFile>>>((ref) {
  final hierarchyState = ref.watch(projectHierarchyServiceProvider);
  final allFiles = <DocumentFile>[];
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