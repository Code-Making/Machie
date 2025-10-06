// lib/project/services/project_hierarchy_service.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker/talker.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import '../../settings/settings_notifier.dart';

// (Logging categories remain the same)
final _penLifecycle = AnsiPen()..cyan(bold: true);
final _penLazyLoad = AnsiPen()..magenta();
final _penBackground = AnsiPen()..blue();
final _penEvents = AnsiPen()..yellow();

// (FileTreeNode class remains the same)
class FileTreeNode {
  final DocumentFile file;
  FileTreeNode(this.file);
}

class ProjectHierarchyService extends Notifier<Map<String, AsyncValue<List<FileTreeNode>>>> {
  @override
  Map<String, AsyncValue<List<FileTreeNode>>> build() {
    final talker = ref.read(talkerProvider);
    talker.logCustom(HierararchyLog($1));

    // --- THIS IS THE FULLY CORRECTED LISTENER SETUP ---

    // 1. Listen for project changes to initialize or clear the hierarchy.
    ref.listen<String?>(
      appNotifierProvider.select((s) => s.value?.currentProject?.id),
      (previousId, nextId) {
        if (nextId != null) {
          final project = ref.read(appNotifierProvider).value!.currentProject!;
          talker.logCustom(HierararchyLog('[HierarchyService] Project changed to "${project.name}" ($nextId). Initializing.', pen: _penLifecycle));
          _initializeHierarchy(project);
        } else {
          talker.logCustom(HierararchyLog('[HierarchyService] Project closed. Clearing state.', pen: _penLifecycle));
          state = {};
        }
      },
      fireImmediately: true,
    );

    // 2. Listen for file operation events. This listener is set up ONCE.
    ref.listen<AsyncValue<FileOperationEvent>>(
      fileOperationStreamProvider,
      (previous, next) {
        // Get the current project ID each time an event occurs.
        final currentProjectId = ref.read(appNotifierProvider).value?.currentProject?.id;
        if (currentProjectId == null) return; // Ignore events if no project is open

        next.whenData((event) => _handleFileEvent(event));
      },
    );

    // 3. Listen for hidden file setting changes.
    ref.listen<bool>(
      settingsProvider.select((s) {
        final generalSettings = s.pluginSettings[GeneralSettings] as GeneralSettings?;
        return generalSettings?.showHiddenFiles ?? false;
      }),
      (previous, next) {
        if (previous != null && previous != next) {
          final project = ref.read(appNotifierProvider).value?.currentProject;
          if (project != null) {
            talker.logCustom(HierararchyLog('[HierarchyService] Hidden file visibility changed to $next. Reloading hierarchy.', pen: _penLifecycle));
            _initializeHierarchy(project);
          }
        }
      },
    );

    return {};
  }

  // --- The rest of the logic is now sound ---

  void _handleFileEvent(FileOperationEvent event) {
      final repo = ref.read(projectRepositoryProvider);
      final talker = ref.read(talkerProvider);
      if (repo == null) return;

      switch (event) {
        case FileCreateEvent(createdFile: final file):
          final parentUri = repo.fileHandler.getParentUri(file.uri);
          talker.logCustom(FileOperationLog(' Create: "${file.name}" in "$parentUri"'));
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
          talker.logCustom(FileOperationLog(' Delete: "${file.name}" from "$parentUri"'));
          final parentAsyncValue = state[parentUri];
          if (parentAsyncValue is AsyncData<List<FileTreeNode>>) {
            final parentContents = parentAsyncValue.value;
            state = {...state, parentUri: AsyncData(parentContents.where((node) => node.file.uri != file.uri).toList())};
          }
          if (file.isDirectory) {
            if (state.containsKey(file.uri)) {
              talker.logCustom(FileOperationLog(' Removing deleted directory from cache: "${file.uri}"'));
              final newState = Map<String, AsyncValue<List<FileTreeNode>>>.from(state)..remove(file.uri);
              state = newState;
            }
          }
          break;
        
        case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
          final sourceParentUri = repo.fileHandler.getParentUri(oldFile.uri);
          final destParentUri = repo.fileHandler.getParentUri(newFile.uri);
          talker.logCustom(FileOperationLog(' Rename/Move: "${oldFile.name}" -> "${newFile.name}"'));
          
          final newState = Map<String, AsyncValue<List<FileTreeNode>>>.from(state);
          
          final sourceParentAsyncValue = newState[sourceParentUri];
          if (sourceParentAsyncValue is AsyncData<List<FileTreeNode>>) {
            final sourceContents = sourceParentAsyncValue.value;
            newState[sourceParentUri] = AsyncData(sourceContents.where((node) => node.file.uri != oldFile.uri).toList());
          }

          final destParentAsyncValue = newState[destParentUri];
          if (destParentAsyncValue is AsyncData<List<FileTreeNode>>) {
            final destContents = destParentAsyncValue.value;
            if (!destContents.any((node) => node.file.uri == newFile.uri)) {
                newState[destParentUri] = AsyncData([...destContents, FileTreeNode(newFile)]);
            }
          }

          if (oldFile.isDirectory) {
            talker.logCustom(FileOperationLog(' Invalidating cache for renamed folder: ${oldFile.uri}'));
            final keysToRemove = newState.keys.where((key) => key.startsWith(oldFile.uri)).toList();
            for (final key in keysToRemove) {
              newState.remove(key);
            }
          }
          
          state = newState;
          break;
      }
  }

  // REMOVED _listenForFileChanges method as it's now inline in build()

  Future<void> _initializeHierarchy(Project project) async {
    ref.read(talkerProvider).log('[HierarchyService] _initializeHierarchy starting.', pen: _penLifecycle);
    state = {};
    final rootNodes = await loadDirectory(project.rootUri);
    if (rootNodes != null) {
      _startFullBackgroundScan(project);
    }
  }

  // (loadDirectory and _startFullBackgroundScan are unchanged from the last correct version)
  Future<List<FileTreeNode>?> loadDirectory(String uri) async {
    final talker = ref.read(talkerProvider);
    if (state[uri] is AsyncLoading) {
      talker.logCustom(HierararchyLog('[_loadDirectory] Already loading: $uri', pen: _penLazyLoad));
      return null;
    }
    if (state[uri] is AsyncData) {
      talker.logCustom(HierararchyLog('[_loadDirectory] Already in cache: $uri', pen: _penLazyLoad));
      return state[uri]?.value;
    }

    talker.logCustom(HierararchyLog('[_loadDirectory] Fetching from disk: $uri', pen: _penLazyLoad));

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
      talker.logCustom(HierararchyLog('[_loadDirectory] Success (${nodes.length} items): $uri', pen: _penLazyLoad));
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
      talker.logCustom(HierararchyLog('[BackgroundScan] Starting full scan.', pen: _penBackground));
      
      final queue = <String>[project.rootUri];
      final Set<String> processedUris = {project.rootUri};
      int scannedCount = 0;

      while (queue.isNotEmpty) {
        if (ref.read(appNotifierProvider).value?.currentProject?.id != project.id) {
          talker.logCustom(HierararchyLog('[BackgroundScan] Project changed, abandoning scan.', pen: _penBackground));
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
      talker.logCustom(HierararchyLog('[BackgroundScan] Full scan complete. Scanned $scannedCount directories.', pen: _penBackground));
    }));
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