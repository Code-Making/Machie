// lib/widgets/file_explorer_drawer.dart

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_notifier.dart';
import '../plugins/code_editor/code_editor_plugin.dart';
import '../plugins/plugin_models.dart';
import '../plugins/plugin_registry.dart';
import '../data/file_handler/file_handler.dart';
import '../data/file_handler/local_file_handler.dart';
import '../project/project_models.dart';
import '../settings/settings_screen.dart';
import '../utils/clipboard.dart';


// --------------------
// Main Drawer Widget
// --------------------

class FileExplorerDrawer extends ConsumerWidget {
  const FileExplorerDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The drawer's content depends on whether a project is currently open in the app state.
    final currentProject = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject));

    return Drawer(
      width: MediaQuery.of(context).size.width,
      child: currentProject == null
          ? const ProjectSelectionScreen()
          : ProjectExplorerView(project: currentProject),
    );
  }
}

// --------------------
// Project Selection Screen (No Project Open)
// --------------------

class ProjectSelectionScreen extends ConsumerWidget {
  const ProjectSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get the list of known projects from the global app state.
    final knownProjects = ref.watch(appNotifierProvider.select((s) => s.value?.knownProjects)) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Project'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Button to open a project from the device's file system.
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Project'),
            onPressed: () async {
              final fileHandler = LocalFileHandlerFactory.create();
              final pickedDir = await fileHandler.pickDirectory();
              if (pickedDir != null && context.mounted) {
                // Delegate the complex logic of opening to the AppNotifier.
                await ref.read(appNotifierProvider.notifier).openProjectFromFolder(pickedDir);
                Navigator.pop(context); // Close drawer after opening.
              }
            },
          ),
          const Divider(height: 32),
          Text('Recent Projects', style: Theme.of(context).textTheme.titleMedium),
          if (knownProjects.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text('No recent projects. Open one to get started!'),
            ),
          // List of recently opened projects.
          ...knownProjects.map((projectMeta) {
            return ListTile(
              leading: const Icon(Icons.folder),
              title: Text(projectMeta.name),
              subtitle: Text(projectMeta.rootUri, overflow: TextOverflow.ellipsis),
              onTap: () async {
                await ref.read(appNotifierProvider.notifier).openKnownProject(projectMeta.id);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ],
      ),
    );
  }
}

// --------------------
// Project Explorer View (A Project Is Open)
// --------------------

class ProjectExplorerView extends ConsumerWidget {
  final Project project;

  const ProjectExplorerView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cast to LocalProject to access UI-specific properties like view mode.
    // This is safe because the UI is only shown for local projects for now.
    final localProject = project as LocalProject;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: MediaQuery.of(context).size.width * 0.75,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: ProjectDropdown(currentProject: project),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // File/folder count will be implemented later.
                const Text(''),
                FileExplorerModeDropdown(currentMode: localProject.fileExplorerViewMode),
              ],
            ),
          ),
        ),
      ),
      body: _DirectoryView(
        directory: localProject.rootUri,
        projectRootUri: localProject.rootUri,
        expandedFolders: localProject.expandedFolders,
      ),
      bottomNavigationBar: _FileOperationsFooter(project: localProject),
    );
  }
}

// --------------------
// UI Components
// --------------------

class ProjectDropdown extends ConsumerWidget {
  final Project currentProject;
  const ProjectDropdown({super.key, required this.currentProject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects = ref.watch(appNotifierProvider.select((s) => s.value?.knownProjects)) ?? [];
    final appNotifier = ref.read(appNotifierProvider.notifier);

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: currentProject.id,
        onChanged: (projectId) {
          if (projectId == '_manage_projects') {
            Navigator.pop(context);
            showModalBottomSheet(context: context, builder: (ctx) => const ManageProjectsScreen());
          } else if (projectId != null && projectId != currentProject.id) {
            appNotifier.openKnownProject(projectId);
          }
        },
        isExpanded: true,
        items: [
          ...knownProjects.map((proj) => DropdownMenuItem(
                value: proj.id,
                child: Text(proj.name, overflow: TextOverflow.ellipsis),
              )),
          const DropdownMenuItem(
            value: '_manage_projects',
            child: Text('Manage Projects...', style: TextStyle(fontStyle: FontStyle.italic)),
          ),
        ],
        selectedItemBuilder: (BuildContext context) {
          // The selected item builder needs to return a list of widgets that matches
          // the length of the items list.
          return [
            ...knownProjects.map<Widget>((proj) {
              return Row(
                children: [
                  Flexible(
                    child: Text(
                      proj.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down),
                ],
              );
            }),
            const Text(''), // Placeholder for the 'Manage Projects' item.
          ];
        },
        iconSize: 0,
        isDense: true,
      ),
    );
  }
}

class ManageProjectsScreen extends ConsumerWidget {
  const ManageProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appNotifierProvider).value;
    final knownProjects = appState?.knownProjects ?? [];
    final appNotifier = ref.read(appNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Projects')),
      body: ListView.builder(
        itemCount: knownProjects.length,
        itemBuilder: (context, index) {
          final project = knownProjects[index];
          final isCurrent = appState?.currentProject?.id == project.id;
          return ListTile(
            leading: Icon(isCurrent ? Icons.folder_open : Icons.folder),
            title: Text(project.name + (isCurrent ? ' (Current)' : '')),
            subtitle: Text(project.rootUri, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Remove from list',
              onPressed: () async {
                final confirm = await _showConfirmDialog(
                  context,
                  title: 'Remove "${project.name}"?',
                  content: 'This will only remove the project from your recent projects list. The folder and its contents on your device will not be deleted.',
                );
                if (confirm) {
                  await appNotifier.removeKnownProject(project.id);
                }
              },
            ),
            onTap: isCurrent ? null : () async {
              await appNotifier.openKnownProject(project.id);
              Navigator.pop(context);
            },
          );
        },
      ),
      // NEW: Add a FloatingActionButton to open new projects.
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final fileHandler = LocalFileHandlerFactory.create();
          final pickedDir = await fileHandler.pickDirectory();
          if (pickedDir != null && context.mounted) {
            // Delegate opening logic to the notifier.
            await appNotifier.openProjectFromFolder(pickedDir);
            // Close the manage screen after opening.
            Navigator.pop(context);
          }
        },
        tooltip: 'Open Project',
        child: const Icon(Icons.folder_open),
      ),
    );
  }

  Future<bool> _showConfirmDialog(BuildContext context, {required String title, required String content}) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    ) ?? false;
  }
}

class FileExplorerContextCommands {
  static List<FileContextCommand> getCommands(WidgetRef ref, DocumentFile item) {
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final clipboardContent = ref.watch(clipboardProvider);
    final currentProject = ref.read(appNotifierProvider).value?.currentProject;

    return [
      BaseFileContextCommand(
        id: 'rename',
        label: 'Rename',
        icon: const Icon(Icons.edit),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true,
        executeFor: (ref, item) async {
          final newName = await _showTextInputDialog(ref.context, title: 'Rename', initialValue: item.name);
          if (newName != null && newName.isNotEmpty && newName != item.name) {
            await appNotifier.performFileOperation(
              (handler) => handler.renameDocumentFile(item, newName)
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
          final confirm = await _showConfirmDialog(ref.context, title: 'Delete ${item.name}?', content: 'This action cannot be undone.');
          if (confirm) {
            await appNotifier.performFileOperation(
              (handler) => handler.deleteDocumentFile(item)
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
          ref.read(clipboardProvider.notifier).state = ClipboardItem(uri: item.uri, isFolder: item.isDirectory, operation: ClipboardOperation.cut);
        },
      ),
      BaseFileContextCommand(
        id: 'copy',
        label: 'Copy',
        icon: const Icon(Icons.content_copy),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true,
        executeFor: (ref, item) async {
          ref.read(clipboardProvider.notifier).state = ClipboardItem(uri: item.uri, isFolder: item.isDirectory, operation: ClipboardOperation.copy);
        },
      ),
      BaseFileContextCommand(
        id: 'paste',
        label: 'Paste',
        icon: const Icon(Icons.content_paste),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => item.isDirectory && clipboardContent != null,
        executeFor: (ref, item) async {
          if (clipboardContent == null || currentProject == null) return;
          final sourceFile = await currentProject.fileHandler.getFileMetadata(clipboardContent.uri);
          if (sourceFile == null) {
            ref.read(logProvider.notifier).add('Clipboard source file not found.');
            appNotifier.clearClipboard();
            return;
          }

          await appNotifier.performFileOperation((handler) async {
            if (clipboardContent.operation == ClipboardOperation.copy) {
              await handler.copyDocumentFile(sourceFile, item.uri);
            } else { // Cut
              await handler.moveDocumentFile(sourceFile, item.uri);
            }
          });
          appNotifier.clearClipboard();
        },
      ),
    ];
  }

  static Future<String?> _showTextInputDialog(BuildContext context, {required String title, String? initialValue}) {
    TextEditingController controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'New Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('OK')),
        ],
      ),
    );
  }
  
  static Future<bool> _showConfirmDialog(BuildContext context, {required String title, required String content}) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    ) ?? false;
  }
}

class _DirectoryView extends ConsumerWidget {
  final String directory;
  final String projectRootUri;
  final Set<String> expandedFolders;

  const _DirectoryView({
    required this.directory,
    required this.projectRootUri,
    required this.expandedFolders,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(currentProjectDirectoryContentsProvider(directory));

    return contentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (contents) {
        final viewMode = (ref.read(appNotifierProvider).value?.currentProject as LocalProject?)?.fileExplorerViewMode;
        _applySorting(contents, viewMode);

        return ListView.builder(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: contents.length,
          itemBuilder: (context, index) {
            final item = contents[index];
            final depth = item.uri.split('%2F').length - projectRootUri.split('%2F').length;
            return _DirectoryItem(
              item: item,
              depth: depth,
              isExpanded: expandedFolders.contains(item.uri),
            );
          },
        );
      },
    );
  }

  void _applySorting(List<DocumentFile> contents, FileExplorerViewMode? mode) {
    contents.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (mode) {
        case FileExplorerViewMode.sortByNameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case FileExplorerViewMode.sortByDateModified:
          return b.modifiedDate.compareTo(a.modifiedDate);
        default:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
  }
}

class _DirectoryItem extends ConsumerWidget {
  final DocumentFile item;
  final int depth;
  final bool isExpanded;

  const _DirectoryItem({required this.item, required this.depth, required this.isExpanded});

  void _showContextMenu(BuildContext context, WidgetRef ref, DocumentFile item) {
    final allCommands = FileExplorerContextCommands.getCommands(ref, item)
      .where((cmd) => cmd.canExecuteFor(ref, item))
      .toList();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(item.name, style: Theme.of(context).textTheme.titleLarge),
            ),
            const Divider(),
            ...allCommands.map((command) => ListTile(
              leading: command.icon,
              title: Text(command.label),
              onTap: () {
                Navigator.pop(ctx);
                command.executeFor(ref, item);
              },
            )).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final project = ref.watch(appNotifierProvider.select((s) => s.value!.currentProject! as LocalProject));

    Widget childWidget;
    if (item.isDirectory) {
      childWidget = ExpansionTile(
        key: ValueKey(item.uri),
        leading: Icon(isExpanded ? Icons.folder_open : Icons.folder, color: Colors.yellow),
        title: Text(item.name),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          appNotifier.toggleFolderExpansion(item.uri);
        },
        childrenPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
        children: [
          if (isExpanded)
            _DirectoryView(
              directory: item.uri,
              projectRootUri: project.rootUri,
              expandedFolders: project.expandedFolders,
            ),
        ],
      );
    } else {
      childWidget = ListTile(
        contentPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
        leading: FileTypeIcon(file: item),
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        onTap: () {
          appNotifier.openFile(item);
          Navigator.pop(context);
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
  final LocalProject project;
  const _FileOperationsFooter({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipboardContent = ref.watch(clipboardProvider);
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final logNotifier = ref.read(logProvider.notifier);
    
    final rootDoc = _RootPlaceholder(project.rootUri);
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
              final newFileName = await FileExplorerContextCommands._showTextInputDialog(context, title: 'New File');
              if (newFileName != null && newFileName.isNotEmpty) {
                try {
                  await appNotifier.performFileOperation(
                    (handler) => handler.createDocumentFile(project.rootUri, newFileName, isDirectory: false)
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
              final newFolderName = await FileExplorerContextCommands._showTextInputDialog(context, title: 'New Folder');
              if (newFolderName != null && newFolderName.isNotEmpty) {
                try {
                  await appNotifier.performFileOperation(
                    (handler) => handler.createDocumentFile(project.rootUri, newFolderName, isDirectory: true)
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
              // Use a temporary handler to pick a file from anywhere on the device.
              final pickerHandler = LocalFileHandlerFactory.create();
              final pickedFile = await pickerHandler.pickFile();
              if (pickedFile != null) {
                try {
                  // Use the project's handler to copy the picked file into the project root.
                  await appNotifier.performFileOperation(
                    (projectHandler) => projectHandler.copyDocumentFile(pickedFile, project.rootUri)
                  );
                } catch (e) {
                  logNotifier.add('Error importing file: $e');
                }
              }
            },
          ),
          // --- Paste ---
          IconButton(
            icon: Icon(Icons.content_paste, color: clipboardContent != null ? Theme.of(context).colorScheme.primary : Colors.grey),
            tooltip: 'Paste',
            onPressed: (pasteCommand != null && pasteCommand.canExecuteFor(ref, rootDoc))
              ? () => pasteCommand.executeFor(ref, rootDoc)
              : null,
          ),
          // --- Close Drawer ---
          IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
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

// Helper to get an appropriate icon for a file type.
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

// Stubs for other widgets to avoid breaking the file, these would be fleshed out.
class FileExplorerModeDropdown extends StatelessWidget {
  final FileExplorerViewMode currentMode;
  const FileExplorerModeDropdown({super.key, required this.currentMode});
  @override
  Widget build(BuildContext context) => const Icon(Icons.sort);
}