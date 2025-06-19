// lib/explorer/common/file_explorer_commands.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../command/command_models.dart';
import '../../data/file_handler/file_handler.dart';
import '../../editors/plugins/plugin_models.dart';
import '../../editors/plugins/plugin_registry.dart';
import '../../utils/clipboard.dart';
import 'file_explorer_dialogs.dart';
import '../../utils/toast.dart';

// A private dummy command class to represent a divider in the list.
class _DividerCommand extends FileContextCommand {
  const _DividerCommand()
    : super(
        id: 'divider',
        label: '',
        icon: const SizedBox.shrink(),
        sourcePlugin: '',
      );

  @override
  bool canExecuteFor(WidgetRef ref, DocumentFile item) => true;

  @override
  Future<void> executeFor(WidgetRef ref, DocumentFile item) async {}
}

void showFileContextMenu(
  BuildContext context,
  WidgetRef ref,
  DocumentFile item,
) {
  // 1. Find all plugins that can open this file.
  final compatiblePlugins =
      ref
          .read(activePluginsProvider)
          .where((p) => p.supportsFile(item))
          .toList();

  // 2. Get all commands, including the dynamically generated "Open With..." commands.
  final allCommands =
      FileContextCommands.getCommands(
        ref,
        item,
        compatiblePlugins,
      ).where((cmd) => cmd.canExecuteFor(ref, item)).toList();

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
                ...allCommands.map((command) {
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
    DocumentFile item,
    List<EditorPlugin> compatiblePlugins,
  ) {
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final clipboardContent = ref.watch(clipboardProvider);
    final currentProject = ref.read(appNotifierProvider).value?.currentProject;

    final List<FileContextCommand> commands = [];

    // Dynamically generate "Open With..." commands if there are multiple options.
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
              final result = await appNotifier.openFile(
                item,
                explicitPlugin: plugin,
              );
              final context = ref.context;
              if (result is OpenFileSuccess && context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              } else if (result is OpenFileError && context.mounted) {
                MachineToast.error(result.message);
              }
            },
          ),
        );
      }
      commands.add(const _DividerCommand());
    }

    // Add the standard file operation commands.
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
            await appNotifier.performFileOperation(
              (handler) => handler.renameDocumentFile(item, newName),
            );
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
            await appNotifier.performFileOperation(
              (handler) => handler.deleteDocumentFile(item),
            );
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
            (ref, item) => item.isDirectory && clipboardContent != null,
        executeFor: (ref, item) async {
          if (clipboardContent == null || currentProject == null) return;
          final sourceFile = await currentProject.fileHandler.getFileMetadata(
            clipboardContent.uri,
          );
          if (sourceFile == null) {
            /*ref
                .read(logProvider.notifier)
                .add('Clipboard source file not found.');*/
            appNotifier.clearClipboard();
            return;
          }

          await appNotifier.performFileOperation((handler) async {
            if (clipboardContent.operation == ClipboardOperation.copy) {
              await handler.copyDocumentFile(sourceFile, item.uri);
            } else {
              // Cut
              await handler.moveDocumentFile(sourceFile, item.uri);
            }
          });
          appNotifier.clearClipboard();
        },
      ),
    ]);

    return commands;
  }
}
