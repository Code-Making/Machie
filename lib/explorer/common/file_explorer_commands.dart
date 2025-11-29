// =========================================
// UPDATED: lib/explorer/common/file_explorer_commands.dart
// =========================================

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../command/command_models.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project/project_repository.dart';
import '../../editor/plugins/editor_plugin_registry.dart';
import '../../utils/clipboard.dart';
import '../../utils/toast.dart';
import '../../widgets/dialogs/file_explorer_dialogs.dart';
import '../services/explorer_service.dart';

class _DividerCommand extends FileContextCommand {
  const _DividerCommand()
    : super(
        id: 'divider',
        label: '',
        icon: const SizedBox.shrink(),
        sourcePlugin: '',
      );
  @override
  bool canExecuteFor(WidgetRef ref, ProjectDocumentFile item) => true;
  @override
  Future<void> executeFor(WidgetRef ref, ProjectDocumentFile item) async {}
}

void showFileContextMenu(
  BuildContext context,
  WidgetRef ref,
  ProjectDocumentFile item,
) {
  final compatiblePlugins =
      ref
          .read(activePluginsProvider)
          .where((p) => p.supportsFile(item))
          .toList();

  final List<FileContextCommand> allCommands = [];

  // 1. Add commands from ALL compatible plugins first.
  for (final plugin in compatiblePlugins) {
    allCommands.addAll(plugin.getFileContextMenuCommands(item));
  }

  final generalCommands = FileContextCommands.getCommands(
    ref,
    item,
    compatiblePlugins,
  );

  // 2. Add a divider if there were plugin commands and there will be general commands.
  if (allCommands.isNotEmpty && generalCommands.isNotEmpty) {
    allCommands.add(const _DividerCommand());
  }

  // 3. Add the general commands.
  allCommands.addAll(generalCommands);

  final executableCommands =
      allCommands.where((cmd) => cmd.canExecuteFor(ref, item)).toList();

  showModalBottomSheet(
    context: context,
    builder:
        (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(),
                ...executableCommands.map((command) {
                  // <-- Use the newly constructed list
                  if (command is _DividerCommand) {
                    return const Divider(height: 1, indent: 16, endIndent: 16);
                  }
                  return ListTile(
                    leading: command.icon,
                    title: Text(command.label),
                    onTap: () {
                      Navigator.pop(ctx);
                      command.executeFor(ref, item);
                    },
                  );
                }),
              ],
            ),
          ),
        ),
  );
}

class FileContextCommands {
  static List<FileContextCommand> getCommands(
    WidgetRef ref,
    ProjectDocumentFile item,
    List<EditorPlugin> compatiblePlugins,
  ) {
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final clipboardContent = ref.watch(clipboardProvider);
    final repo = ref.read(projectRepositoryProvider);
    final explorerService = ref.read(explorerServiceProvider);

    final List<FileContextCommand> commands = [];

    // THE FIX: Add directory-specific commands first if the item is a directory.
    if (item.isDirectory) {
      commands.addAll([
        BaseFileContextCommand(
          id: 'new_file_in_folder',
          label: 'New File',
          icon: const Icon(Icons.note_add_outlined),
          sourcePlugin: 'FileExplorer',
          canExecuteFor: (ref, item) => item.isDirectory,
          executeFor: (ref, item) async {
            final newName = await showTextInputDialog(
              ref.context,
              title: 'New File',
            );
            if (newName != null && newName.isNotEmpty) {
              // Use the item's URI as the parent URI for the new file.
              await explorerService.createFile(item.uri, newName);
            }
          },
        ),
        BaseFileContextCommand(
          id: 'new_folder_in_folder',
          label: 'New Folder',
          icon: const Icon(Icons.create_new_folder_outlined),
          sourcePlugin: 'FileExplorer',
          canExecuteFor: (ref, item) => item.isDirectory,
          executeFor: (ref, item) async {
            final newName = await showTextInputDialog(
              ref.context,
              title: 'New Folder',
            );
            if (newName != null && newName.isNotEmpty) {
              // Use the item's URI as the parent URI for the new folder.
              await explorerService.createFolder(item.uri, newName);
            }
          },
        ),
        const _DividerCommand(),
      ]);
    }

    if (!item.isDirectory && compatiblePlugins.length > 1) {
      for (final plugin in compatiblePlugins) {
        commands.add(
          BaseFileContextCommand(
            id: 'open_with_${plugin.name.replaceAll(' ', '_')}',
            label: 'Open with ${plugin.name}',
            icon: plugin.icon,
            sourcePlugin: 'FileExplorer',
            canExecuteFor: (ref, item) => true,
            executeFor: (ref, item) async {
              await appNotifier.openFileInEditor(item, explicitPlugin: plugin);
            },
          ),
        );
      }
      commands.add(const _DividerCommand());
    }

    commands.addAll([
      BaseFileContextCommand(
        id: 'rename',
        label: 'Rename',
        icon: const Icon(Icons.edit),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true,
        executeFor: (ref, item) async {
          final newName = await showTextInputDialog(
            ref.context,
            title: 'Rename',
            initialValue: item.name,
          );
          if (newName != null && newName.isNotEmpty && newName != item.name) {
            await explorerService.renameItem(item, newName);
          }
        },
      ),
      BaseFileContextCommand(
        id: 'delete',
        label: 'Delete',
        icon: const Icon(Icons.delete, color: Colors.redAccent),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true,
        executeFor: (ref, item) async {
          final confirm = await showConfirmDialog(
            ref.context,
            title: 'Delete ${item.name}?',
            content: 'This action cannot be undone.',
          );
          if (confirm) {
            await explorerService.deleteItem(item);
          }
        },
      ),
      BaseFileContextCommand(
        id: 'cut',
        label: 'Cut',
        icon: const Icon(Icons.content_cut),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true,
        executeFor: (ref, item) async {
          ref.read(clipboardProvider.notifier).state = ClipboardItem(
            uri: item.uri,
            isFolder: item.isDirectory,
            operation: ClipboardOperation.cut,
          );
        },
      ),
      BaseFileContextCommand(
        id: 'copy',
        label: 'Copy',
        icon: const Icon(Icons.content_copy),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true,
        executeFor: (ref, item) async {
          ref.read(clipboardProvider.notifier).state = ClipboardItem(
            uri: item.uri,
            isFolder: item.isDirectory,
            operation: ClipboardOperation.copy,
          );
        },
      ),
      BaseFileContextCommand(
        id: 'paste',
        label: 'Paste',
        icon: const Icon(Icons.content_paste),
        sourcePlugin: 'FileExplorer',
        canExecuteFor:
            (ref, item) =>
                item.isDirectory && clipboardContent != null && repo != null,
        executeFor: (ref, item) async {
          if (clipboardContent == null) return;
          try {
            await explorerService.pasteItem(item, clipboardContent);
            appNotifier.clearClipboard();
          } catch (e) {
            MachineToast.error(e.toString());
            appNotifier.clearClipboard();
          }
        },
      ),
    ]);

    return commands;
  }
}
