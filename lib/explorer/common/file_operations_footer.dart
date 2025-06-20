// lib/explorer/common/file_operations_footer.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/local_file_handler.dart';
import '../../logs/logs_provider.dart';
import '../../utils/clipboard.dart';
import '../plugins/file_explorer/file_explorer_state.dart';
import 'file_explorer_commands.dart';
import 'file_explorer_dialogs.dart';
import 'file_explorer_widgets.dart';

class FileOperationsFooter extends ConsumerWidget {
  final String projectRootUri;
  final String projectId;
  const FileOperationsFooter({
    super.key,
    required this.projectRootUri,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipboardContent = ref.watch(clipboardProvider);
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final talker = ref.read(talkerProvider);

    final rootDoc = RootPlaceholder(projectRootUri);
    final pasteCommand = FileContextCommands.getCommands(
      ref,
      rootDoc,
      [],
    ).firstWhereOrNull((cmd) => cmd.id == 'paste');

    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // --- New File ---
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'New File',
            onPressed: () async {
              final newFileName = await showTextInputDialog(
                context,
                title: 'New File',
              );
              if (newFileName != null && newFileName.isNotEmpty) {
                try {
                  await appNotifier.performFileOperation(
                    (repo) => repo.createDocumentFile( // REFACTOR: Use repo
                      projectRootUri,
                      newFileName,
                      isDirectory: false,
                    ),
                  );
                  talker.info('Created new file: $newFileName');
                } catch (e, st) {
                  talker.handle(e, st, 'Error creating file');
                }
              }
            },
          ),
          // --- New Folder ---
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New Folder',
            onPressed: () async {
              final newFolderName = await showTextInputDialog(
                context,
                title: 'New Folder',
              );
              if (newFolderName != null && newFolderName.isNotEmpty) {
                try {
                  await appNotifier.performFileOperation(
                    (repo) => repo.createDocumentFile( // REFACTOR: Use repo
                      projectRootUri,
                      newFolderName,
                      isDirectory: true,
                    ),
                  );
                } catch (e, st) {
                  talker.handle(e, st, 'Error creating folder');
                }
              }
            },
          ),
          // --- Import File ---
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import File',
            onPressed: () async {
              // This part requires an external file handler, which is correct.
              final pickerHandler = LocalFileHandlerFactory.create();
              final pickedFile = await pickerHandler.pickFile();
              if (pickedFile != null) {
                try {
                  await appNotifier.performFileOperation(
                    (projectRepo) => projectRepo.copyDocumentFile( // REFACTOR: Use repo
                      pickedFile,
                      projectRootUri,
                    ),
                  );
                } catch (e, st) {
                  talker.handle(e, st, 'Error importing file');
                }
              }
            },
          ),
          // --- Paste ---
          IconButton(
            icon: Icon(
              Icons.content_paste,
              color: clipboardContent != null
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            tooltip: 'Paste',
            onPressed: (pasteCommand != null &&
                    pasteCommand.canExecuteFor(ref, rootDoc))
                ? () => pasteCommand.executeFor(ref, rootDoc)
                : null,
          ),
          // --- Sort ---
          IconButton(
            icon: const Icon(Icons.sort_by_alpha),
            tooltip: 'Sort',
            onPressed: () => _showSortOptions(context, ref),
          ),
          // --- Close Drawer ---
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showSortOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Sort by Name (A-Z)'),
                onTap: () {
                  // REFACTOR: Use the new notifier provider
                  ref
                      .read(fileExplorerNotifierProvider(projectId))
                      .setViewMode(FileExplorerViewMode.sortByNameAsc);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Sort by Name (Z-A)'),
                onTap: () {
                  ref
                      .read(fileExplorerNotifierProvider(projectId))
                      .setViewMode(FileExplorerViewMode.sortByNameDesc);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Sort by Date Modified'),
                onTap: () {
                  ref
                      .read(fileExplorerNotifierProvider(projectId))
                      .setViewMode(FileExplorerViewMode.sortByDateModified);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}