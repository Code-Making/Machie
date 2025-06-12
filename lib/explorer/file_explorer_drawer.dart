// lib/explorer/file_explorer_drawer.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../app/app_notifier.dart';
import '../data/file_handler/local_file_handler.dart';
import '../project/project_models.dart';
import 'explorer_plugin_models.dart';
import 'explorer_plugin_registry.dart';
import 'new_project_screen.dart';
import '../project/workspace_service.dart';

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
      width: MediaQuery.of(context).size.width * 0.85, // A bit wider for better usability
      child: currentProject == null
          ? const ProjectSelectionScreen()
          : ExplorerHostView(project: currentProject),
    );
  }
}

// --------------------
// Explorer Host View (A Project Is Open)
// --------------------

class ExplorerHostView extends ConsumerStatefulWidget {
  final Project project;

  const ExplorerHostView({super.key, required this.project});

  @override
  ConsumerState<ExplorerHostView> createState() => _ExplorerHostViewState();
}

class _ExplorerHostViewState extends ConsumerState<ExplorerHostView> {
  @override
  void initState() {
    super.initState();
    // Use WidgetsBinding to ensure the ref is available after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeActiveExplorer();
      }
    });
  }

  Future<void> _initializeActiveExplorer() async {
    // CORRECTED: Read the service first, then pass it to the project method.
    final workspaceService = ref.read(workspaceServiceProvider);
    final activePluginId = await widget.project.loadActiveExplorer(workspaceService: workspaceService);

    if (mounted && activePluginId != null) {
      final registry = ref.read(explorerRegistryProvider);
      final activePlugin =
          registry.firstWhereOrNull((p) => p.id == activePluginId);
      if (activePlugin != null) {
        ref.read(activeExplorerProvider.notifier).state = activePlugin;
      }
    }
  }

  // MODIFIED: build method signature is now correct for a ConsumerState.
  @override
  Widget build(BuildContext context) {
    // 'ref' is accessed as a property of the State class.
    final activeExplorer = ref.watch(activeExplorerProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: ProjectSwitcherDropdown(currentProject: widget.project),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ExplorerTypeDropdown(currentProject: widget.project),
          ),
        ),
      ),
      body: activeExplorer.build(ref, widget.project),
    );
  }
}

// --------------------
// UI Components
// --------------------

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
            // CORRECTED: Read the service first, then pass it to the project method.
            final workspaceService = ref.read(workspaceServiceProvider);
            currentProject.saveActiveExplorer(plugin.id, workspaceService: workspaceService);
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


class ProjectSwitcherDropdown extends ConsumerWidget {
  final Project currentProject;
  const ProjectSwitcherDropdown({super.key, required this.currentProject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects =
        ref.watch(appNotifierProvider.select((s) => s.value?.knownProjects)) ?? [];
    final appNotifier = ref.read(appNotifierProvider.notifier);

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: currentProject.id,
        onChanged: (projectId) {
          if (projectId == '_manage_projects') {
            Navigator.pop(context); // Close drawer before opening modal
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
          final displayedProject = knownProjects.firstWhere(
            (p) => p.id == currentProject.id,
            orElse: () => currentProject.metadata,
          );
          return knownProjects.map<Widget>((item) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                displayedProject.name,
                style: Theme.of(context).textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList()
            ..add(const SizedBox.shrink());
        },
        icon: const Icon(Icons.arrow_drop_down),
        iconSize: 24,
      ),
    );
  }
}

class ProjectSelectionScreen extends ConsumerWidget {
  const ProjectSelectionScreen({super.key});

  void _showNewProjectScreen(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const NewProjectScreen(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects =
        ref.watch(appNotifierProvider.select((s) => s.value?.knownProjects)) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Machine'),
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
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Create or Open Project'),
            onPressed: () => _showNewProjectScreen(context),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: Theme.of(context).textTheme.titleMedium,
            ),
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
          ...knownProjects.map((projectMeta) {
            return ListTile(
              leading: Icon(projectMeta.projectTypeId == 'simple_local'
                  ? Icons.folder_copy_outlined
                  : Icons.folder_special_outlined),
              title: Text(projectMeta.name),
              subtitle: Text(
                projectMeta.rootUri,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                await ref
                    .read(appNotifierProvider.notifier)
                    .openKnownProject(projectMeta.id);
                if (context.mounted) Navigator.pop(context);
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

  void _showNewProjectScreen(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const NewProjectScreen(),
    );
  }

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
            leading: Icon(
              isCurrent
                  ? Icons.folder_open
                  : project.projectTypeId == 'simple_local'
                      ? Icons.folder_copy_outlined
                      : Icons.folder_special_outlined,
            ),
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
            onTap: isCurrent
                ? null
                : () async {
                    await appNotifier.openKnownProject(project.id);
                    Navigator.pop(context); // Close the manage screen
                  },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pop(context);
          _showNewProjectScreen(ref.context);
        },
        tooltip: 'Create or Open Project',
        child: const Icon(Icons.add),
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