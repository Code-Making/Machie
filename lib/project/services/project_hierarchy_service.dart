// lib/project/services/project_hierarchy_service.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import '../../settings/settings_notifier.dart'; // <-- ADDED IMPORT

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
    ref.listen<String?>(
      appNotifierProvider.select((s) => s.value?.currentProject?.id),
      (previousId, nextId) {
        if (nextId != null) {
          // The project has changed. Get the full project object.
          final project = ref.read(appNotifierProvider).value!.currentProject!;
          state = {};
          _initializeHierarchy(project);
          _listenForFileChanges(project.id); // Pass project ID for context
        } else {
          state = {}; // A project was closed
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
        // If the setting changes while a project is open, trigger a full reload.
        final project = ref.read(appNotifierProvider).value?.currentProject;
        if (project != null && previous != next) {
          ref.read(talkerProvider).info('Hidden file visibility changed. Reloading file hierarchy.');
          _initializeHierarchy(project);
        }
      },
    );
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
        // Only process events if we are still in the same project context.
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