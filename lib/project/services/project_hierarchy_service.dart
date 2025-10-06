// lib/project/services/project_hierarchy_service.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker/talker.dart'; // Import for AnsiPen

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import '../../settings/settings_notifier.dart';

// --- Logging Categories ---
final _penLifecycle = AnsiPen()..cyan(bold: true);    // For init, start, stop
final _penLazyLoad = AnsiPen()..magenta();             // For on-demand loading
final _penBackground = AnsiPen()..blue();              // For the full background scan
final _penEvents = AnsiPen()..yellow();                // For file system events (create, delete, rename)

// (FileTreeNode class remains the same)
class FileTreeNode {
  final DocumentFile file;
  FileTreeNode(this.file);
}

class ProjectHierarchyService extends Notifier<Map<String, AsyncValue<List<FileTreeNode>>>> {
  @override
  Map<String, AsyncValue<List<FileTreeNode>>> build() {
    final talker = ref.read(talkerProvider);
    talker.log('[HierarchyService] build() called.', pen: _penLifecycle);

    ref.listen<String?>(
      appNotifierProvider.select((s) => s.value?.currentProject?.id),
      (previousId, nextId) {
        if (nextId != null) {
          final project = ref.read(appNotifierProvider).value!.currentProject!;
          talker.log('[HierarchyService] Project changed to "${project.name}" ($nextId). Initializing.', pen: _penLifecycle);
          _initializeHierarchy(project);
          _listenForFileChanges(project.id);
        } else {
          talker.log('[HierarchyService] Project closed. Clearing state.', pen: _penLifecycle);
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
            talker.log('[HierarchyService] Hidden file visibility changed to $next. Reloading hierarchy.', pen: _penLifecycle);
            _initializeHierarchy(project);
          }
        }
      },
    );

    return {};
  }

  Future<void> _initializeHierarchy(Project project) async {
    ref.read(talkerProvider).log('[HierarchyService] _initializeHierarchy starting.', pen: _penLifecycle);
    state = {};
    final rootNodes = await loadDirectory(project.rootUri);
    if (rootNodes != null) {
      _startFullBackgroundScan(project);
    }
  }

  Future<List<FileTreeNode>?> loadDirectory(String uri) async {
    final talker = ref.read(talkerProvider);
    if (state[uri] is AsyncLoading) {
      talker.log('[_loadDirectory] Already loading: $uri', pen: _penLazyLoad);
      return null;
    }
    if (state[uri] is AsyncData) {
      talker.log('[_loadDirectory] Already in cache: $uri', pen: _penLazyLoad);
      return state[uri]?.value;
    }

    talker.log('[_loadDirectory] Fetching from disk: $uri', pen: _penLazyLoad);

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
      talker.log('[_loadDirectory] Success (${nodes.length} items): $uri', pen: _penLazyLoad);
      return nodes;
    } catch (e, st) {
      talker.handle(e, st, '[_loadDirectory] Error: $uri');
      state = {...state, uri: AsyncError(e, st)};
      return null;
    }
  }
  
  void _startFullBackgroundScan(Project project) {
    unawaited(Future(() async {
      final talker = ref.read(talkerProvider);
      talker.log('[BackgroundScan] Starting full scan.', pen: _penBackground);
      
      final queue = <String>[project.rootUri];
      final Set<String> processedUris = {project.rootUri};
      int scannedCount = 0;

      while (queue.isNotEmpty) {
        if (ref.read(appNotifierProvider).value?.currentProject?.id != project.id) {
          talker.log('[BackgroundScan] Project changed, abandoning scan.', pen: _penBackground);
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
        scannedCount++;
        await Future.delayed(Duration.zero);
      }
      talker.log('[BackgroundScan] Full scan complete. Scanned $scannedCount directories.', pen: _penBackground);
    }));
  }

  void _listenForFileChanges(String projectId) {
    final talker = ref.read(talkerProvider);
    talker.log('[FileEvents] Attaching listener for project $projectId', pen: _penEvents);

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
              talker.log('[FileEvents] Create: "${file.name}" in "$parentUri"', pen: _penEvents);
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
              talker.log('[FileEvents] Delete: "${file.name}" from "$parentUri"', pen: _penEvents);
              final parentAsyncValue = state[parentUri];
              if (parentAsyncValue is AsyncData<List<FileTreeNode>>) {
                final parentContents = parentAsyncValue.value;
                state = {...state, parentUri: AsyncData(parentContents.where((node) => node.file.uri != file.uri).toList())};
              }
              if (file.isDirectory) {
                if (state.containsKey(file.uri)) {
                  talker.log('[FileEvents] Removing deleted directory from cache: "${file.uri}"', pen: _penEvents);
                  final newState = Map<String, AsyncValue<List<FileTreeNode>>>.from(state)..remove(file.uri);
                  state = newState;
                }
              }
              break;
            
            case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
              final sourceParentUri = repo.fileHandler.getParentUri(oldFile.uri);
              final destParentUri = repo.fileHandler.getParentUri(newFile.uri);
              talker.log('[FileEvents] Rename/Move: "${oldFile.name}" -> "${newFile.name}"', pen: _penEvents);
              talker.log('  Source Parent: $sourceParentUri', pen: _penEvents);
              talker.log('  Dest Parent:   $destParentUri', pen: _penEvents);

              final newState = Map<String, AsyncValue<List<FileTreeNode>>>.from(state);
              
              // 1. Remove from source
              final sourceParentAsyncValue = newState[sourceParentUri];
              if (sourceParentAsyncValue is AsyncData<List<FileTreeNode>>) {
                final sourceContents = sourceParentAsyncValue.value;
                newState[sourceParentUri] = AsyncData(sourceContents.where((node) => node.file.uri != oldFile.uri).toList());
              }

              // 2. Add to destination
              final destParentAsyncValue = newState[destParentUri];
              if (destParentAsyncValue is AsyncData<List<FileTreeNode>>) {
                final destContents = destParentAsyncValue.value;
                if (!destContents.any((node) => node.file.uri == newFile.uri)) {
                   newState[destParentUri] = AsyncData([...destContents, FileTreeNode(newFile)]);
                }
              }

              // 3. Invalidate old directory cache
              if (oldFile.isDirectory) {
                talker.log('[FileEvents] Invalidating cache for renamed folder: ${oldFile.uri}', pen: _penEvents);
                final keysToRemove = newState.keys.where((key) => key.startsWith(oldFile.uri)).toList();
                for (final key in keysToRemove) {
                  newState.remove(key);
                }
              }
              
              state = newState;
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