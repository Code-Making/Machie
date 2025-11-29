// lib/project/services/project_hierarchy_service.dart

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project/project_repository.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import '../../settings/settings_notifier.dart';

// (FileTreeNode class remains the same)
class FileTreeNode {
  final ProjectDocumentFile file;
  FileTreeNode(this.file);
}

class ProjectHierarchyService
    extends Notifier<Map<String, AsyncValue<List<FileTreeNode>>>> {
  @override
  Map<String, AsyncValue<List<FileTreeNode>>> build() {
    final talker = ref.read(talkerProvider);
    talker.logCustom(HierarchyLog('[HierarchyService] build() called.'));

    // --- THIS IS THE FULLY CORRECTED LISTENER SETUP ---

    // 1. Listen for project changes to initialize or clear the hierarchy.
    ref.listen<String?>(
      appNotifierProvider.select((s) => s.value?.currentProject?.id),
      (previousId, nextId) {
        if (nextId != null) {
          final project = ref.read(appNotifierProvider).value!.currentProject!;
          talker.logCustom(
            HierarchyLog(
              '[HierarchyService] Project changed to "${project.name}" ($nextId). Initializing.',
            ),
          );
          _initializeHierarchy(project);
        } else {
          talker.logCustom(
            HierarchyLog('[HierarchyService] Project closed. Clearing state.'),
          );
          state = {};
        }
      },
      fireImmediately: true,
    );

    // 2. Listen for file operation events. This listener is set up ONCE.
    ref.listen<AsyncValue<FileOperationEvent>>(fileOperationStreamProvider, (
      previous,
      next,
    ) {
      // Get the current project ID each time an event occurs.
      final currentProjectId =
          ref.read(appNotifierProvider).value?.currentProject?.id;
      if (currentProjectId == null) {
        return; // Ignore events if no project is open
      }

      next.whenData((event) => _handleFileEvent(event));
    });

    // 3. Listen for hidden file setting changes.
    ref.listen<bool>(
      effectiveSettingsProvider.select((s) {
        final generalSettings =
            s.pluginSettings[GeneralSettings] as GeneralSettings?;
        return generalSettings?.showHiddenFiles ?? false;
      }),
      (previous, next) {
        if (previous != null && previous != next) {
          final project = ref.read(appNotifierProvider).value?.currentProject;
          if (project != null) {
            talker.logCustom(
              HierarchyLog(
                '[HierarchyService] Hidden file visibility changed to $next. Reloading hierarchy.',
              ),
            );
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
        talker.logCustom(
          FileOperationLog(' Create: "${file.name}" in "$parentUri"'),
        );
        final parentAsyncValue = state[parentUri];
        if (parentAsyncValue is AsyncData<List<FileTreeNode>>) {
          final parentContents = parentAsyncValue.value;
          if (!parentContents.any((node) => node.file.uri == file.uri)) {
            state = {
              ...state,
              parentUri: AsyncData([...parentContents, FileTreeNode(file)]),
            };
          }
        }
        break;

      case FileDeleteEvent(deletedFile: final file):
        final parentUri = repo.fileHandler.getParentUri(file.uri);
        talker.logCustom(
          FileOperationLog(' Delete: "${file.name}" from "$parentUri"'),
        );
        final parentAsyncValue = state[parentUri];
        if (parentAsyncValue is AsyncData<List<FileTreeNode>>) {
          final parentContents = parentAsyncValue.value;
          state = {
            ...state,
            parentUri: AsyncData(
              parentContents
                  .where((node) => node.file.uri != file.uri)
                  .toList(),
            ),
          };
        }
        if (file.isDirectory) {
          if (state.containsKey(file.uri)) {
            talker.logCustom(
              FileOperationLog(
                ' Removing deleted directory from cache: "${file.uri}"',
              ),
            );
            final newState = Map<String, AsyncValue<List<FileTreeNode>>>.from(
              state,
            )..remove(file.uri);
            state = newState;
          }
        }
        break;

      case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
        final sourceParentUri = repo.fileHandler.getParentUri(oldFile.uri);
        final destParentUri = repo.fileHandler.getParentUri(newFile.uri);
        talker.logCustom(
          FileOperationLog(
            ' Rename/Move: "${oldFile.name}" -> "${newFile.name}"',
          ),
        );

        final newState = Map<String, AsyncValue<List<FileTreeNode>>>.from(
          state,
        );

        final sourceParentAsyncValue = newState[sourceParentUri];
        if (sourceParentAsyncValue is AsyncData<List<FileTreeNode>>) {
          final sourceContents = sourceParentAsyncValue.value;
          newState[sourceParentUri] = AsyncData(
            sourceContents
                .where((node) => node.file.uri != oldFile.uri)
                .toList(),
          );
        }

        final destParentAsyncValue = newState[destParentUri];
        if (destParentAsyncValue is AsyncData<List<FileTreeNode>>) {
          final destContents = destParentAsyncValue.value;
          if (!destContents.any((node) => node.file.uri == newFile.uri)) {
            newState[destParentUri] = AsyncData([
              ...destContents,
              FileTreeNode(newFile),
            ]);
          }
        }

        if (oldFile.isDirectory) {
          talker.logCustom(
            FileOperationLog(
              ' Invalidating cache for renamed folder: ${oldFile.uri}',
            ),
          );
          final keysToRemove =
              newState.keys
                  .where((key) => key.startsWith(oldFile.uri))
                  .toList();
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
    ref
        .read(talkerProvider)
        .logCustom(
          HierarchyLog('[HierarchyService] _initializeHierarchy starting.'),
        );
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
      talker.logCustom(HierarchyLog('[_loadDirectory] Already loading: $uri'));
      return null;
    }
    if (state[uri] is AsyncData) {
      talker.logCustom(HierarchyLog('[_loadDirectory] Already in cache: $uri'));
      return state[uri]?.value;
    }

    talker.logCustom(HierarchyLog('[_loadDirectory] Fetching from disk: $uri'));

    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return null;

    state = {...state, uri: const AsyncLoading()};

    try {
      final showHidden = ref.read(
        effectiveSettingsProvider.select((s) {
          final generalSettings =
              s.pluginSettings[GeneralSettings] as GeneralSettings?;
          return generalSettings?.showHiddenFiles ?? false;
        }),
      );
      final items = await repo.listDirectory(uri, includeHidden: showHidden);
      final nodes = items.map((file) => FileTreeNode(file)).toList();
      state = {...state, uri: AsyncData(nodes)};
      talker.logCustom(
        HierarchyLog('[_loadDirectory] Success (${nodes.length} items): $uri'),
      );
      return nodes;
    } catch (e, st) {
      talker.handle(e, st, '[_loadDirectory] Error: $uri');
      state = {...state, uri: AsyncError(e, st)};
      return null;
    }
  }

  void _startFullBackgroundScan(Project project) {
    unawaited(
      Future(() async {
        final talker = ref.read(talkerProvider);
        talker.logCustom(HierarchyLog('[BackgroundScan] Starting full scan.'));

        final queue = <String>[project.rootUri];
        final Set<String> processedUris = {project.rootUri};
        int scannedCount = 0;

        while (queue.isNotEmpty) {
          if (ref.read(appNotifierProvider).value?.currentProject?.id !=
              project.id) {
            talker.logCustom(
              HierarchyLog(
                '[BackgroundScan] Project changed, abandoning scan.',
              ),
            );
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
            if (childNode.file.isDirectory &&
                !processedUris.contains(childNode.file.uri)) {
              queue.add(childNode.file.uri);
              processedUris.add(childNode.file.uri);
            }
          }
          scannedCount++;
          await Future.delayed(Duration.zero);
        }
        talker.logCustom(
          HierarchyLog(
            '[BackgroundScan] Full scan complete. Scanned $scannedCount directories.',
          ),
        );
      }),
    );
  }
}

// --- Providers ---
// (These remain unchanged)
final projectHierarchyServiceProvider = NotifierProvider<
  ProjectHierarchyService,
  Map<String, AsyncValue<List<FileTreeNode>>>
>(ProjectHierarchyService.new);

final flatFileIndexProvider =
    Provider.autoDispose<AsyncValue<List<ProjectDocumentFile>>>((ref) {
      final hierarchyState = ref.watch(projectHierarchyServiceProvider);
      final allFiles = <ProjectDocumentFile>[];
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

final directoryContentsProvider = Provider.family
    .autoDispose<AsyncValue<List<FileTreeNode>>?, String>((ref, directoryUri) {
      final hierarchyState = ref.watch(projectHierarchyServiceProvider);
      return hierarchyState[directoryUri];
    });
