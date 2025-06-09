// lib/widgets/file_explorer_drawer.dart

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_notifier.dart';
import '../plugins/code_editor/code_editor_plugin.dart';
import '../plugins/plugin_architecture.dart';
import '../plugins/plugin_registry.dart';
import '../project/file_handler/file_handler.dart';
import '../project/file_handler/local_file_handler.dart';
import '../project/project_models.dart';
import '../screens/settings_screen.dart';

// --------------------
// File Explorer Providers
// --------------------

// This provider fetches the contents of a specific directory URI.
// It gets the correct FileHandler from the currently active project in AppState.
final currentProjectDirectoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String>((ref, uri) async {
  final handler = ref.watch(appNotifierProvider).value?.currentProject?.fileHandler;
  if (handler == null) return [];

  // Prevent listing arbitrary URIs outside the current project's scope.
  final projectRoot = ref.watch(appNotifierProvider).value?.currentProject?.rootUri;
  if (projectRoot != null && !uri.startsWith(projectRoot)) {
    return [];
  }

  return handler.listDirectory(uri);
});

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
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (contents) {
        // Apply sorting based on the current project's view mode.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appNotifier = ref.read(appNotifierProvider.notifier);
    final project = ref.watch(appNotifierProvider).value!.currentProject as LocalProject;

    Widget childWidget;
    if (item.isDirectory) {
      childWidget = ExpansionTile(
        key: ValueKey(item.uri),
        leading: Icon(isExpanded ? Icons.folder_open : Icons.folder, color: Colors.yellow),
        title: Text(item.name),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          // This will be implemented in the notifier
          // appNotifier.toggleFolderExpansion(item.uri);
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
    return childWidget;
  }
}

class _FileOperationsFooter extends ConsumerWidget {
  final LocalProject project;

  const _FileOperationsFooter({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This footer provides quick actions for file/folder creation.
    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(icon: const Icon(Icons.note_add_outlined), tooltip: 'New File', onPressed: () {}),
          IconButton(icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New Folder', onPressed: () {}),
          IconButton(icon: const Icon(Icons.file_upload_outlined), tooltip: 'Import File', onPressed: () {}),
          IconButton(icon: const Icon(Icons.content_paste), tooltip: 'Paste', onPressed: null), // Disabled for now
          IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
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