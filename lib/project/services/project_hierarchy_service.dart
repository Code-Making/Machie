// lib/project/services/project_hierarchy_service.dart
import 'dart.async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import '../../settings/settings_notifier.dart';

// (FileTreeNode class remains the same)
class FileTreeNode {
  final DocumentFile file;
  FileTreeNode(this.file);
}

class ProjectHierarchyService extends Notifier<Map<String, AsyncValue<List<FileTreeNode>>>> {
  @override
  Map<String, AsyncValue<List<FileTreeNode>>> build() {
    ref.listen<String?>(
      appNotifierProvider.select((s) => s.value?.currentProject?.id),
      (previousId, nextId) {
        if (nextId != null) {
          final project = ref.read(appNotifierProvider).value!.currentProject!;
          _initializeHierarchy(project);
          _listenForFileChanges(project.id);
        } else {
          state = {};
        }
      },
      fireImmediately: true,
    );

    ref.listen<bool>(
      settingsProvider.select((s) {
        final generalSettings = s.pluginSettings[GeneralSettings] as GeneralSettings?;
        return generalSettings?.showHiddenFiles ?? false;
      }),
      (previous, next) {
        if (previous != null && previous != next) {
          final project = ref.read(appNotifierProvider).value?.currentProject;
          if (project != null) {
            ref.read(talkerProvider).info('Hidden file visibility changed. Reloading file hierarchy.');
            _initializeHierarchy(project);
          }
        }
      },
    );

    return {};
  }

  Future<void> _initializeHierarchy(Project project) async {
    state = {};
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
      final showHidden = ref.read(settingsProvider.select((s) {
        final generalSettings = s.pluginSettings[GeneralSettings] as GeneralSettings?;
        return generalSettings?.showHiddenFiles ?? false;
      }));
      final items = await repo.listDirectory(uri, includeHidden: showHidden);
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

  void _listenForFileChanges(String projectId) {
    ref.listen<AsyncValue<FileOperationEvent>>(
      fileOperationStreamProvider,
      (previous, next) {
        if (ref.read(appNotifierProvider).value?.currentProject?.id != projectId) {
          return;
        }

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
            
            // --- THIS IS THE NEW, EFFICIENT RENAME LOGIC ---
            case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
              final parentUri = repo.fileHandler.getParentUri(newFile.uri);
              final parentAsyncValue = state[parentUri];

              // 1. Update the parent's listing
              if (parentAsyncValue is AsyncData<List<FileTreeNode>>) {
                final parentContents = parentAsyncValue.value;
                final newParentContents = parentContents.where((node) => node.file.uri != oldFile.uri).toList();
                newParentContents.add(FileTreeNode(newFile));
                state = {...state, parentUri: AsyncData(newParentContents)};
              }

              // 2. If a directory was renamed, invalidate its cache and all descendant caches.
              if (oldFile.isDirectory) {
                final talker = ref.read(talkerProvider);
                talker.info("Invalidating cache for renamed folder: ${oldFile.uri}");
                
                // Create a mutable copy of the state map
                final newState = Map<String, AsyncValue<List<FileTreeNode>>>.from(state);
                
                // Find all keys that represent the old directory or its children
                final keysToRemove = newState.keys.where((key) => key.startsWith(oldFile.uri)).toList();
                
                // Remove them all
                for (final key in keysToRemove) {
                  newState.remove(key);
                }
                
                // Update the state with the pruned map. The UI will now lazy-load the new paths.
                state = newState;
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