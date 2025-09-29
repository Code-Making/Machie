// =========================================
// UPDATED: lib/project/services/project_file_index.dart
// =========================================

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// REMOVED: Unused import for 'collection'.

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';

/// A provider that maintains a flat list of all files for the current project.
///
/// It builds the index once when a project is opened and then keeps it
/// in sync by listening to file operation events. This provides a highly
/// performant way for features like "Search" or "Go to File" to access
/// the project's file structure.
final projectFileIndexProvider = StateNotifierProvider.autoDispose<
    ProjectFileIndex, AsyncValue<List<DocumentFile>>>(
  (ref) => ProjectFileIndex(ref),
);

class ProjectFileIndex
    extends StateNotifier<AsyncValue<List<DocumentFile>>> {
  final Ref _ref;
  // THE FIX: Changed type from StreamSubscription to ProviderSubscription.
  ProviderSubscription? _fileOpSubscription;

  ProjectFileIndex(this._ref) : super(const AsyncValue.loading()) {
    // Listen for changes in the current project.
    _ref.listen<Project?>(
      appNotifierProvider.select((s) => s.value?.currentProject),
      (previous, next) {
        // When the project changes (or closes), cancel old listeners and rebuild.
        // THE FIX: Changed .cancel() to .close().
        _fileOpSubscription?.close();
        if (next != null) {
          _buildIndex(next);
          // Start listening to file operations for the new project context.
          _listenForFileChanges();
        } else {
          // No project is open, so the index is empty.
          state = const AsyncValue.data([]);
        }
      },
      fireImmediately: true,
    );
  }

  /// Performs the initial, recursive scan of the project directory.
  Future<void> _buildIndex(Project project) async {
    state = const AsyncValue.loading();
    final repo = _ref.read(projectRepositoryProvider);
    final talker = _ref.read(talkerProvider);

    if (repo == null) {
      state = AsyncValue.error('Project is not open.', StackTrace.current);
      return;
    }

    talker.info('[ProjectFileIndex] Starting to build index...');

    try {
      final allFiles = <DocumentFile>[];
      final directoriesToScan = <DocumentFile>[
        // Create a placeholder for the root to start the scan
        VirtualDocumentFile(uri: project.rootUri, name: project.name, isDirectory: true)
      ];
      final scannedUris = <String>{};

      while (directoriesToScan.isNotEmpty) {
        final currentDir = directoriesToScan.removeAt(0);
        if (scannedUris.contains(currentDir.uri)) continue;
        scannedUris.add(currentDir.uri);

        final items = await repo.listDirectory(currentDir.uri);
        for (final item in items) {
          if (item.isDirectory) {
            directoriesToScan.add(item);
          } else {
            allFiles.add(item);
          }
        }
      }

      talker.info('[ProjectFileIndex] Index build complete. Found ${allFiles.length} files.');
      if (mounted) {
        state = AsyncValue.data(allFiles);
      }
    } catch (e, st) {
      talker.handle(e, st, '[ProjectFileIndex] Failed to build index.');
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// Subscribes to the file operation stream to keep the index in sync.
  void _listenForFileChanges() {
    _fileOpSubscription = _ref.listen<AsyncValue<FileOperationEvent>>(
      fileOperationStreamProvider,
      (previous, next) {
        next.whenData((event) {
          // We only update if the current state is fully loaded (not loading/error).
          if (state is! AsyncData<List<DocumentFile>>) return;

          final currentFiles = state.value!;

          switch (event) {
            case FileCreateEvent(createdFile: final file):
              // Only add if it's not a directory.
              if (!file.isDirectory) {
                state = AsyncValue.data([...currentFiles, file]);
              }
              break;
            case FileDeleteEvent(deletedFile: final file):
              state = AsyncValue.data(
                currentFiles.where((f) => f.uri != file.uri).toList(),
              );
              break;
            case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
              // If a folder was renamed, we need a full rebuild.
              if (newFile.isDirectory) {
                final project = _ref.read(appNotifierProvider).value!.currentProject!;
                _buildIndex(project);
              } else {
                // If it was just a file, we can swap it out.
                final index = currentFiles.indexWhere((f) => f.uri == oldFile.uri);
                if (index != -1) {
                  final updatedFiles = List<DocumentFile>.from(currentFiles);
                  updatedFiles[index] = newFile;
                  state = AsyncValue.data(updatedFiles);
                }
              }
              break;
          }
        });
      },
    );
  }

  @override
  void dispose() {
    // THE FIX: Changed .cancel() to .close().
    _fileOpSubscription?.close();
    super.dispose();
  }
}