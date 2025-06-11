// lib/explorer/file_explorer_drawer.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_notifier.dart';
import '../data/file_handler/local_file_handler.dart';
import '../project/project_models.dart';
import 'explorer_plugin_models.dart';
import 'explorer_plugin_registry.dart';

// --------------------
// Main Drawer Widget (The "Host")
// --------------------

class FileExplorerDrawer extends ConsumerWidget {
  const FileExplorerDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentProject = ref.watch(
      appNotifierProvider.select((s) => s.value?.currentProject),
    );

    return Drawer(
      width: MediaQuery.of(context).size.width,
      child: currentProject == null
          ? const ProjectSelectionScreen()
          : ExplorerHostView(project: currentProject),
    );
  }
}

// --------------------
// Explorer Host View (A Project Is Open)
// --------------------

class ExplorerHostView extends ConsumerWidget {
  final Project project;

  const ExplorerHostView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the active explorer provider to decide which plugin to render.
    final activeExplorer = ref.watch(activeExplorerProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        // MODIFIED: Use the title for the project dropdown for better alignment.
        title: ProjectSwitcherDropdown(currentProject: project),
        // Global actions like settings are still here.
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
        // MODIFIED: Use the 'bottom' property for the second line of controls.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            // The explorer type dropdown is now here.
            child: ExplorerTypeDropdown(currentProject: project),
          ),
        ),
      ),
      // The body dynamically builds the widget from the active explorer plugin.
      body: activeExplorer.build(ref, project),
    );
  }
}

// --- UI Components ---
// MODIFIED: ExplorerTypeDropdown is now simpler, as it's just one line.
class ExplorerTypeDropdown extends ConsumerWidget {
  final Project currentProject;
  const ExplorerTypeDropdown({super.key, required this.currentProject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(explorerRegistryProvider);
    final activeExplorer = ref.watch(activeExplorerProvider);

    return DropdownButtonHideUnderline(
      child: DropdownButton<ExplorerPlugin>(
        value: activeExplorer,
        onChanged: (plugin) {
          if (plugin != null) {
            ref.read(activeExplorerProvider.notifier).state = plugin;
          }
        },
        isExpanded: true,
        items: registry.map((plugin) {
          return DropdownMenuItem(
            value: plugin,
            child: Row(
              children: [
                Icon(plugin.icon, size: 20),
                const SizedBox(width: 12),
                Text(plugin.name, overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// MODIFIED: ProjectSwitcherDropdown's selected item builder uses a larger font.
class ProjectSwitcherDropdown extends ConsumerWidget {
  final Project currentProject;
  const ProjectSwitcherDropdown({super.key, required this.currentProject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects =
        ref.watch(appNotifierProvider.select((s) => s.value?.knownProjects)) ??
            [];
    final appNotifier = ref.read(appNotifierProvider.notifier);

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: currentProject.id,
        onChanged: (projectId) {
          if (projectId == '_manage_projects') {
            Navigator.pop(context);
            showModalBottomSheet(
              context: context,
              builder: (ctx) => const ManageProjectsScreen(),
            );
          } else if (projectId != null && projectId != currentProject.id) {
            appNotifier.openKnownProject(projectId);
          }
        },
        isExpanded: true,
        items: [
          ...knownProjects.map(
            (proj) => DropdownMenuItem(
              value: proj.id,
              child: Text(proj.name, overflow: TextOverflow.ellipsis),
            ),
          ),
          const DropdownMenuItem(
            value: '_manage_projects',
            child: Text(
              'Manage Projects...',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        ],
        selectedItemBuilder: (BuildContext context) {
          // Find the current project to display its name
          final displayedProject = knownProjects.firstWhere(
            (p) => p.id == currentProject.id,
            orElse: () => currentProject.metadata, // Fallback
          );
          // The builder must return a list of widgets matching the items length
          return knownProjects.map<Widget>((item) {
            // This widget is only shown for the selected item
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                displayedProject.name,
                style: Theme.of(context).textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList()..add(const SizedBox.shrink()); // Add placeholder for manage item
        },
        icon: const Icon(Icons.arrow_drop_down),
        iconSize: 24,
      ),
    );
  }
}

// ... (ProjectSelectionScreen and ManageProjectsScreen are unchanged) ...
class ProjectSelectionScreen extends ConsumerWidget {
  const ProjectSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get the list of known projects from the global app state.
    final knownProjects =
        ref.watch(appNotifierProvider.select((s) => s.value?.knownProjects)) ??
        [];

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
                await ref
                    .read(appNotifierProvider.notifier)
                    .openProjectFromFolder(pickedDir);
                Navigator.pop(context); // Close drawer after opening.
              }
            },
          ),
          const Divider(height: 32),
          Text(
            'Recent Projects',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
              subtitle: Text(
                projectMeta.rootUri,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                await ref
                    .read(appNotifierProvider.notifier)
                    .openKnownProject(projectMeta.id);
                Navigator.pop(context);
              },
            );
          }),
        ],
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
                  content:
                      'This will only remove the project from your recent projects list. The folder and its contents on your device will not be deleted.',
                );
                if (confirm) {
                  await appNotifier.removeKnownProject(project.id);
                }
              },
            ),
            onTap:
                isCurrent
                    ? null
                    : () async {
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

  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
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