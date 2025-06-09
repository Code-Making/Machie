// =========================================
// FILE: lib/widgets/file_explorer_drawer.dart
// =========================================

import 'dart:math';
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// These imports would point to the new architectural files.
// For now, their existence is assumed based on the plan.
// import '../app/app_state.dart';
// import '../project/project_interface.dart';
// import '../project/project_manager.dart';

import '../file_system/file_handler.dart';
import '../main.dart';
import '../plugins/plugin_architecture.dart';
import '../plugins/plugin_registry.dart';
import '../project/project_models.dart';
import '../screens/settings_screen.dart';
import '../session/session_management.dart'; // Still needed for some models

// NOTE: The code below is written against the NEW architecture.
// It assumes `appProvider` and `Project` methods exist as planned.
// For this example, I'll mock a simple `appProvider` and `Project` class
// at the top so the file is self-contained and demonstrates the concept.

// =========================================================================
// MOCK IMPLEMENTATION FOR DEMONSTRATION (would be in separate files)
// =========================================================================

// Mock Project class
abstract class Project {
  String get id;
  String get name;
  String get rootUri;
  Set<String> get expandedFolders;
  FileExplorerViewMode get fileExplorerViewMode;
  Future<List<DocumentFile>> listDirectory(String uri);
  Future<void> openFileInSession(DocumentFile file);
  Future<void> createFile(String parentUri, String name);
  Future<void> createDirectory(String parentUri, String name);
  Future<void> importFile(DocumentFile source, String destinationUri);
  Future<void> paste(ClipboardItem item, String destinationUri);
}

// Mock AppState
class AppState {
  final Project? activeProject;
  final List<ProjectMetadata> knownProjects;
  const AppState({this.activeProject, this.knownProjects = const []});
}

// Mock AppNotifier
class AppNotifier extends Notifier<AppState> {
  @override
  AppState build() => const AppState();
  Future<void> openProjectFromFolder(DocumentFile folder) async { /* ... */ }
  Future<void> switchProject(String id) async { /* ... */ }
  Future<void> removeKnownProject(String id) async { /* ... */ }
  void updateProjectExplorerMode(FileExplorerViewMode mode) { /* ... */ }
  void toggleFolderExpansion(String uri) { /* ... */ }
}

final appProvider = NotifierProvider<AppNotifier, AppState>(AppNotifier.new);

// =========================================================================
// END MOCK IMPLEMENTATION
// =========================================================================

// This new provider will get the directory contents by calling the project's method.
final directoryContentsProvider = FutureProvider.autoDispose.family<List<DocumentFile>, String>((ref, uri) {
  final activeProject = ref.watch(appProvider.select((s) => s.activeProject));
  if (activeProject == null) {
    return Future.value([]);
  }
  // DELEGATION: The UI asks the project to list its own files.
  return activeProject.listDirectory(uri);
});


/// The main drawer widget. It acts as a router, showing the project selection
/// screen or the file explorer based on whether a project is active.
class FileExplorerDrawer extends ConsumerWidget {
  const FileExplorerDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The drawer's content is determined by the global AppState.
    final activeProject = ref.watch(appProvider.select((state) => state.activeProject));

    return Drawer(
      width: MediaQuery.of(context).size.width,
      child: activeProject == null
          ? const ProjectSelectionScreen()
          : ProjectExplorerView(project: activeProject),
    );
  }
}


/// A screen for selecting a project when none are open.
class ProjectSelectionScreen extends ConsumerWidget {
  const ProjectSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects = ref.watch(appProvider.select((state) => state.knownProjects));
    final appNotifier = ref.read(appProvider.notifier);
    final fileHandler = ref.read(fileHandlerProvider);

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
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Project'),
            onPressed: () async {
              final pickedDir = await fileHandler.pickDirectory();
              if (pickedDir != null) {
                // DELEGATION: Tell the AppNotifier to handle opening the folder.
                await appNotifier.openProjectFromFolder(pickedDir);
                if (context.mounted) Navigator.pop(context);
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
          ...knownProjects.map((projectMetadata) => ListTile(
            leading: const Icon(Icons.folder),
            title: Text(projectMetadata.name),
            subtitle: Text(projectMetadata.rootUri, overflow: TextOverflow.ellipsis),
            onTap: () async {
              // DELEGATION: Tell the AppNotifier to switch to this project.
              await appNotifier.switchProject(projectMetadata.id);
              if (context.mounted) Navigator.pop(context);
            },
          )),
        ],
      ),
    );
  }
}

/// The main file explorer view for an active project.
class ProjectExplorerView extends StatelessWidget {
  final Project project;

  const ProjectExplorerView({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
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
                // Use a FutureBuilder to get file/folder counts from the project.
                FutureBuilder<List<DocumentFile>>(
                  future: project.listDirectory(project.rootUri),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();
                    final files = snapshot.data!;
                    final fileCount = files.where((f) => !f.isDirectory).length;
                    final folderCount = files.where((f) => f.isDirectory).length;
                    return Text(
                      '$fileCount files, $folderCount folders',
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
                FileExplorerModeDropdown(currentMode: project.fileExplorerViewMode),
              ],
            ),
          ),
        ),
      ),
      body: _DirectoryView(
        project: project,
        directoryUri: project.rootUri,
      ),
      bottomNavigationBar: _FileOperationsFooter(project: project),
    );
  }
}

/// Dropdown for switching between projects or managing them.
class ProjectDropdown extends ConsumerWidget {
  final Project currentProject;
  const ProjectDropdown({super.key, required this.currentProject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects = ref.watch(appProvider.select((s) => s.knownProjects));
    final appNotifier = ref.read(appProvider.notifier);

    // Create a combined list for dropdown items to match the builder's length
    final dropdownItems = [...knownProjects, null]; // null represents the manage option

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: currentProject.id,
        isExpanded: true,
        onChanged: (projectId) {
          if (projectId == '_manage_projects') {
            Navigator.pop(context);
            showModalBottomSheet(context: context, builder: (ctx) => const ManageProjectsScreen());
          } else if (projectId != null) {
            appNotifier.switchProject(projectId);
          }
        },
        items: dropdownItems.map((proj) {
          if (proj == null) {
            return const DropdownMenuItem(
              value: '_manage_projects',
              child: Text('Manage Projects...', style: TextStyle(fontStyle: FontStyle.italic)),
            );
          }
          return DropdownMenuItem(
            value: proj.id,
            child: Text(proj.name, overflow: TextOverflow.ellipsis),
          );
        }).toList(),
        selectedItemBuilder: (context) {
          return dropdownItems.map<Widget>((proj) {
            if (proj == null) return const SizedBox.shrink(); // Hidden in selected view
            return Row(
              children: [
                Flexible(child: Text(currentProject.name, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis)),
                const Icon(Icons.arrow_drop_down),
              ],
            );
          }).toList();
        },
        iconSize: 0,
        isDense: true,
      ),
    );
  }
}

/// Dropdown for changing the file sorting and filtering mode.
class FileExplorerModeDropdown extends ConsumerWidget {
  final FileExplorerViewMode currentMode;
  const FileExplorerModeDropdown({super.key, required this.currentMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appNotifier = ref.read(appProvider.notifier);
    return DropdownButtonHideUnderline(
      child: DropdownButton<FileExplorerViewMode>(
        value: currentMode,
        onChanged: (mode) {
          if (mode != null) {
            // DELEGATION: Update the project's state via the AppNotifier.
            appNotifier.updateProjectExplorerMode(mode);
          }
        },
        items: FileExplorerViewMode.values.map((mode) => DropdownMenuItem(value: mode, child: Text(_getModeDisplayName(mode)))).toList(),
        icon: const Icon(Icons.sort),
        isDense: true,
      ),
    );
  }
  String _getModeDisplayName(FileExplorerViewMode mode) {
    switch (mode) {
      case FileExplorerViewMode.sortByNameAsc: return 'Sort by Name (A-Z)';
      case FileExplorerViewMode.sortByNameDesc: return 'Sort by Name (Z-A)';
      case FileExplorerViewMode.sortByDateModified: return 'Sort by Date Modified';
      case FileExplorerViewMode.showAllFiles: return 'Show All Files';
      case FileExplorerViewMode.showOnlyCode: return 'Show Only Code';
    }
  }
}

/// A modal screen for removing projects from the known projects list.
class ManageProjectsScreen extends ConsumerWidget {
  const ManageProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appProvider);
    final knownProjects = appState.knownProjects;
    final appNotifier = ref.read(appProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Projects')),
      body: ListView.builder(
        itemCount: knownProjects.length,
        itemBuilder: (context, index) {
          final project = knownProjects[index];
          final isCurrent = appState.activeProject?.id == project.id;
          return ListTile(
            leading: Icon(isCurrent ? Icons.folder_open : Icons.folder),
            title: Text(project.name + (isCurrent ? ' (Current)' : '')),
            subtitle: Text(project.rootUri, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final confirm = await _showConfirmDialog(context,
                  title: 'Remove "${project.name}"?',
                  content: 'This will only remove the project from your history. The files will not be deleted.',
                );
                if (confirm) {
                  // DELEGATION: Tell the AppNotifier to remove the project.
                  appNotifier.removeKnownProject(project.id);
                }
              },
            ),
            onTap: isCurrent ? null : () async {
              await appNotifier.switchProject(project.id);
              if (context.mounted) Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
  Future<bool> _showConfirmDialog(BuildContext context, {required String title, required String content}) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(content), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm'))
    ])) ?? false;
  }
}

/// The bottom navigation bar with file operation actions.
class _FileOperationsFooter extends ConsumerWidget {
  final Project project;
  const _FileOperationsFooter({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipboardContent = ref.watch(clipboardProvider);

    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(Icons.edit_document, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Create New File',
            onPressed: () => _handleCreate(context, ref, project, isDirectory: false),
          ),
          IconButton(
            icon: Icon(Icons.create_new_folder, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Create New Folder',
            onPressed: () => _handleCreate(context, ref, project, isDirectory: true),
          ),
          IconButton(
            icon: Icon(Icons.file_upload, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Import File',
            onPressed: () async {
              final fileToImport = await ref.read(fileHandlerProvider).pickFile();
              if (fileToImport != null) {
                // DELEGATION: Ask the project to handle the import.
                await project.importFile(fileToImport, project.rootUri);
                ref.invalidate(directoryContentsProvider(project.rootUri));
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.content_paste, color: clipboardContent != null ? Theme.of(context).colorScheme.primary : Colors.grey),
            tooltip: 'Paste',
            onPressed: clipboardContent != null ? () async {
              // DELEGATION: Ask the project to handle the paste.
              await project.paste(clipboardContent, project.rootUri);
              ref.read(clipboardProvider.notifier).state = null;
              ref.invalidate(directoryContentsProvider(project.rootUri));
            } : null,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close File Explorer',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCreate(BuildContext context, WidgetRef ref, Project project, {required bool isDirectory}) async {
    final title = isDirectory ? 'New Folder Name' : 'New File Name';
    final name = await _showTextInputDialog(context, title: title, labelText: 'Name');
    if (name != null && name.isNotEmpty) {
      if (isDirectory) {
        // DELEGATION: Ask the project to create the directory.
        await project.createDirectory(project.rootUri, name);
      } else {
        // DELEGATION: Ask the project to create the file.
        await project.createFile(project.rootUri, name);
      }
      ref.invalidate(directoryContentsProvider(project.rootUri));
    }
  }

  Future<String?> _showTextInputDialog(BuildContext context, {required String title, required String labelText}) {
    TextEditingController controller = TextEditingController();
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: TextField(controller: controller, decoration: InputDecoration(labelText: labelText), autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('OK'))]));
  }
}

/// Renders the recursive file tree.
class _DirectoryView extends ConsumerWidget {
  final Project project;
  final String directoryUri;

  const _DirectoryView({required this.project, required this.directoryUri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(directoryContentsProvider(directoryUri));

    return contentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text("Error: $err")),
      data: (contents) {
        // Here you would apply sorting based on project.fileExplorerViewMode
        return ListView.builder(
          itemCount: contents.length,
          itemBuilder: (context, index) {
            final item = contents[index];
            final depth = item.uri.split('%2F').length - project.rootUri.split('%2F').length;
            return _DirectoryItem(
              project: project,
              item: item,
              depth: depth,
              isExpanded: project.expandedFolders.contains(item.uri),
            );
          },
        );
      },
    );
  }
}

/// Renders a single file or folder item in the tree.
class _DirectoryItem extends ConsumerWidget {
  final Project project;
  final DocumentFile item;
  final int depth;
  final bool isExpanded;

  const _DirectoryItem({required this.project, required this.item, required this.depth, required this.isExpanded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appNotifier = ref.read(appProvider.notifier);

    if (item.isDirectory) {
      return ExpansionTile(
        key: ValueKey(item.uri),
        leading: Icon(isExpanded ? Icons.folder_open : Icons.folder, color: Colors.yellow),
        title: Text(item.name),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          // DELEGATION: Manage expansion state via the AppNotifier.
          appNotifier.toggleFolderExpansion(item.uri);
        },
        childrenPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
        children: [
          if (isExpanded)
            _DirectoryView(
              project: project,
              directoryUri: item.uri,
            ),
        ],
      );
    } else {
      return ListTile(
        contentPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
        leading: FileTypeIcon(file: item),
        title: Row(
          children: [
            Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis)),
            _FileExtensionTag(file: item),
          ],
        ),
        onTap: () {
          // DELEGATION: Tell the project to open this file in its session.
          project.openFileInSession(item);
          Navigator.pop(context);
        },
        onLongPress: () {
          // Context menu actions would also delegate to project methods.
          // e.g., project.renameFile(item, newName).
        },
      );
    }
  }
}

// --- Helper Widgets (unchanged) ---

class _FileExtensionTag extends StatelessWidget {
  final DocumentFile file;
  const _FileExtensionTag({required this.file});

  @override
  Widget build(BuildContext context) {
    if (file.isDirectory) return const SizedBox.shrink();
    final ext = file.name.split('.').last.toUpperCase();
    if (ext.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(4.0)),
      child: Text(ext, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange[300])),
    );
  }
}

class FileTypeIcon extends ConsumerWidget {
  final DocumentFile file;
  const FileTypeIcon({super.key, required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final plugin = plugins.firstWhereOrNull((p) => p.supportsFile(file));
    return plugin?.icon ?? const Icon(Icons.insert_drive_file);
  }
}