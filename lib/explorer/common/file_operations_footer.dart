// lib/explorer/common/file_operations_footer.dart

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/file_handler/local_file_handler.dart';
import '../../logs/logs_provider.dart';
import '../../utils/clipboard.dart';
import '../plugins/file_explorer/file_explorer_state.dart';
import '../services/explorer_service.dart';
import 'file_explorer_commands.dart';
import 'file_explorer_dialogs.dart';
import 'file_explorer_widgets.dart';

import '../explorer_plugin_registry.dart'; // REFACTOR: Import registry
import '../plugins/file_explorer/file_explorer_plugin.dart'; // REFACTOR: Import for type check

class FileOperationsFooter extends ConsumerWidget {
  final String projectRootUri;
  // REFACTOR: This widget no longer needs projectId
  const FileOperationsFooter({super.key, required this.projectRootUri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipboardContent = ref.watch(clipboardProvider);
    final talker = ref.read(talkerProvider);
    final explorerService = ref.read(explorerServiceProvider);
    // REFACTOR: Check which explorer is active to conditionally show the sort button.
    final activeExplorer = ref.watch(activeExplorerProvider);

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
          // ... New File, New Folder, Import File, Paste buttons are unchanged ...
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
                  await explorerService.createFile(projectRootUri, newFileName);
                  talker.info('Created new file: $newFileName');
                } catch (e, st) {
                  talker.handle(e, st, 'Error creating file');
                }
              }
            },
          ),
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
                  await explorerService.createFolder(
                    projectRootUri,
                    newFolderName,
                  );
                } catch (e, st) {
                  talker.handle(e, st, 'Error creating folder');
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import File',
            onPressed: () async {
              final pickerHandler = LocalFileHandlerFactory.create();
              final pickedFile = await pickerHandler.pickFile();
              if (pickedFile != null) {
                try {
                  await explorerService.importFile(pickedFile, projectRootUri);
                } catch (e, st) {
                  talker.handle(e, st, 'Error importing file');
                }
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.content_paste,
              color:
                  clipboardContent != null
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
            ),
            tooltip: 'Paste',
            onPressed:
                (pasteCommand != null &&
                        pasteCommand.canExecuteFor(ref, rootDoc))
                    ? () => pasteCommand.executeFor(ref, rootDoc)
                    : null,
          ),
          // REFACTOR: Conditionally show the sort button.
          if (activeExplorer is FileExplorerPlugin)
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
                  // REFACTOR: Use the generic notifier
                  ref
                      .read(activeExplorerNotifierProvider)
                      .updateSettings(
                        (settings) =>
                            (settings as FileExplorerSettings).copyWith(
                              viewMode: FileExplorerViewMode.sortByNameAsc,
                            ),
                      );
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Sort by Name (Z-A)'),
                onTap: () {
                  ref
                      .read(activeExplorerNotifierProvider)
                      .updateSettings(
                        (settings) =>
                            (settings as FileExplorerSettings).copyWith(
                              viewMode: FileExplorerViewMode.sortByNameDesc,
                            ),
                      );
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Sort by Date Modified'),
                onTap: () {
                  ref
                      .read(activeExplorerNotifierProvider)
                      .updateSettings(
                        (settings) =>
                            (settings as FileExplorerSettings).copyWith(
                              viewMode: FileExplorerViewMode.sortByDateModified,
                            ),
                      );
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
