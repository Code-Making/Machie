// lib/explorer/plugins/file_explorer/file_explorer_view.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/file_handler/local_file_handler.dart';
import '../../../plugins/plugin_models.dart'; // NEW IMPORT
import '../../../plugins/plugin_registry.dart';
import '../../../project/project_models.dart';
import '../../../utils/clipboard.dart';
import '../../../utils/logs.dart';
import 'file_explorer_state.dart';

class FileExplorerView extends ConsumerWidget {
  final Project project;
  const FileExplorerView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // MODIFIED: Watch the new nullable state provider.
    final fileExplorerState = ref.watch(fileExplorerStateProvider(project.id));

    // MODIFIED: Handle the initial loading state (when state is null).
    if (fileExplorerState == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: _DirectoryView(
            directory: project.rootUri,
            projectRootUri: project.rootUri,
            projectId: project.id,
            state: fileExplorerState,
          ),
        ),
        _FileOperationsFooter(
          projectRootUri: project.rootUri,
          projectId: project.id,
        ),
      ],
    );
  }
}

class _DirectoryView extends ConsumerWidget {
  final String directory;
  final String projectRootUri;
  final String projectId;
  final FileExplorerSettings state;

  const _DirectoryView({
    required this.directory,
    required this.projectRootUri,
    required this.projectId,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(
      currentProjectDirectoryContentsProvider(directory),
    );

    return contentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (contents) {
        _applySorting(contents, state.viewMode);

        return ListView.builder(
          key: PageStorageKey(directory), // Preserve scroll position
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: contents.length,
          itemBuilder: (context, index) {
            final item = contents[index];
            final depth = item.uri.split('%2F').length - projectRootUri.split('%2F').length;
            return _DirectoryItem(
              item: item,
              depth: depth,
              isExpanded: state.expandedFolders.contains(item.uri),
              projectId: projectId,
            );
          },
        );
      },
    );
  }

  void _applySorting(List<DocumentFile> contents, FileExplorerViewMode mode) {
    contents.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (mode) {
        case FileExplorerViewMode.sortByNameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case FileExplorerViewMode.sortByDateModified:
          return b.modifiedDate.compareTo(a.modifiedDate);
        default: // Also handles null and sortByNameAsc
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
  }
}

// NEW: A private dummy command class to represent a divider in the list.
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

class _DirectoryItem extends ConsumerWidget {
  final DocumentFile item;
  final int depth;
  final bool isExpanded;
  final String projectId;

  const _DirectoryItem({
    required this.item,
    required this.depth,
    required this.isExpanded,
    required this.projectId,
  });

  void _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    DocumentFile item,
  ) {
    // 1. Find all plugins that can open this file.
    final compatiblePlugins = ref.read(activePluginsProvider)
        .where((p) => p.supportsFile(item))
        .toList();

    // 2. Get all commands, including the dynamically generated "Open With..." commands.
    final allCommands =
        FileExplorerContextCommands.getCommands(ref, item, compatiblePlugins)
            .where((cmd) => cmd.canExecuteFor(ref, item))
            .toList();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView( // Use a scroll view in case of many options
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
              ...allCommands.map(
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
    ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final fileExplorerNotifier = ref.read(fileExplorerStateProvider(projectId).notifier);

    Widget childWidget;
    if (item.isDirectory) {
      childWidget = ExpansionTile(
        key: PageStorageKey<String>(item.uri),
        leading: Icon(
          isExpanded ? Icons.folder_open : Icons.folder,
          color: Colors.yellow.shade700,
        ),
        title: Text(item.name),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          fileExplorerNotifier.toggleFolderExpansion(item.uri);
        },
        childrenPadding: EdgeInsets.only(left: (depth > 0 ? 16.0 : 0)),
        children: [
          if (isExpanded)
            Consumer(builder: (context, ref, _) {
              final currentState = ref.watch(fileExplorerStateProvider(projectId));
              final project = ref.watch(appNotifierProvider).value!.currentProject!;
              if (currentState == null) return const SizedBox.shrink();
              return _DirectoryView(
                directory: item.uri,
                projectRootUri: project.rootUri,
                projectId: projectId,
                state: currentState,
              );
            }),
        ],
      );
    } else {
      childWidget = ListTile(
        contentPadding: EdgeInsets.only(left: (depth) * 16.0 + 16.0),
        leading: FileTypeIcon(file: item),
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        onTap: () {
          appNotifier.openFile(item);
          Navigator.pop(context); // Close the drawer after opening a file
        },
      );
    }

    return GestureDetector(
      onLongPress: () => _showContextMenu(context, ref, item),
      child: childWidget,
    );
  }
}

class _FileOperationsFooter extends ConsumerWidget {
  final String projectRootUri;
  final String projectId;
  const _FileOperationsFooter({required this.projectRootUri, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipboardContent = ref.watch(clipboardProvider);
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final logNotifier = ref.read(logProvider.notifier);

    final rootDoc = _RootPlaceholder(projectRootUri);
    final pasteCommand = FileExplorerContextCommands.getCommands(ref, rootDoc)
        .firstWhereOrNull((cmd) => cmd.id == 'paste');

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
              final newFileName =
                  await FileExplorerContextCommands._showTextInputDialog(
                context,
                title: 'New File',
              );
              if (newFileName != null && newFileName.isNotEmpty) {
                try {
                  await appNotifier.performFileOperation(
                    (handler) => handler.createDocumentFile(
                      projectRootUri,
                      newFileName,
                      isDirectory: false,
                    ),
                  );
                } catch (e) {
                  logNotifier.add('Error creating file: $e');
                }
              }
            },
          ),
          // --- New Folder ---
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New Folder',
            onPressed: () async {
              final newFolderName =
                  await FileExplorerContextCommands._showTextInputDialog(
                context,
                title: 'New Folder',
              );
              if (newFolderName != null && newFolderName.isNotEmpty) {
                try {
                  await appNotifier.performFileOperation(
                    (handler) => handler.createDocumentFile(
                      projectRootUri,
                      newFolderName,
                      isDirectory: true,
                    ),
                  );
                } catch (e) {
                  logNotifier.add('Error creating folder: $e');
                }
              }
            },
          ),
          // --- Import File ---
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import File',
            onPressed: () async {
              final pickerHandler = LocalFileHandlerFactory.create();
              final pickedFile = await pickerHandler.pickFile();
              if (pickedFile != null) {
                try {
                  await appNotifier.performFileOperation(
                    (projectHandler) => projectHandler.copyDocumentFile(
                      pickedFile,
                      projectRootUri,
                    ),
                  );
                } catch (e) {
                  logNotifier.add('Error importing file: $e');
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
            onPressed: (pasteCommand != null && pasteCommand.canExecuteFor(ref, rootDoc))
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
                  ref.read(fileExplorerStateProvider(projectId).notifier)
                      .setViewMode(FileExplorerViewMode.sortByNameAsc);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Sort by Name (Z-A)'),
                onTap: () {
                  ref.read(fileExplorerStateProvider(projectId).notifier)
                      .setViewMode(FileExplorerViewMode.sortByNameDesc);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Sort by Date Modified'),
                onTap: () {
                  ref.read(fileExplorerStateProvider(projectId).notifier)
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

class FileExplorerContextCommands {
  static List<FileContextCommand> getCommands(
    WidgetRef ref,
    DocumentFile item,
  ) {
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final clipboardContent = ref.watch(clipboardProvider);
    final currentProject = ref.read(appNotifierProvider).value?.currentProject;

    final List<FileContextCommand> commands = [];

    // NEW: Dynamically generate "Open With..." commands if there are multiple options.
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
              // Call the AppNotifier with the explicitly chosen plugin.
              await appNotifier.openFile(item, explicitPlugin: plugin);
              // Pop the drawer if the file opens successfully.
              final context = ref.context;
              if (context.mounted) {
                  Navigator.pop(context);
              }
            },
          )
        );
      }
      // Add a divider to separate from other actions.
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
          final newName = await _showTextInputDialog(
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
          final confirm = await _showConfirmDialog(
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
            ref
                .read(logProvider.notifier)
                .add('Clipboard source file not found.');
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

  static Future<String?> _showTextInputDialog(
    BuildContext context, {
    required String title,
    String? initialValue,
  }) {
    TextEditingController controller = TextEditingController(
      text: initialValue,
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _RootPlaceholder implements DocumentFile {
  @override
  final String uri;
  @override
  final bool isDirectory = true;
  @override
  String get name => '';
  @override
  int get size => 0;
  @override
  DateTime get modifiedDate => DateTime.now();
  @override
  String get mimeType => 'inode/directory';
  _RootPlaceholder(this.uri);
}

class FileTypeIcon extends ConsumerWidget {
  final DocumentFile file;
  const FileTypeIcon({super.key, required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final plugin = plugins.firstWhereOrNull((p) => p.supportsFile(file));
    return plugin?.icon ?? const Icon(Icons.article_outlined);
  }
}