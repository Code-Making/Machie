// lib/widgets/file_explorer_drawer.dart

import 'dart:math';
import 'dart:async'; // For Future.delayed

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../file_system/file_handler.dart';
import '../session/session_management.dart';
import '../main.dart'; // For sessionProvider, fileHandlerProvider, logProvider, commandProvider, activePluginsProvider
import '../plugins/plugin_architecture.dart';
import '../plugins/plugin_registry.dart'; // For EditorPlugin, activePluginsProvider
import '../plugins/code_editor/code_editor_plugin.dart'; // For FileTypeIcon
import '../project/project_models.dart'; // For ProjectMetadata, Project, FileExplorerViewMode, ClipboardItem, ClipboardOperation, clipboardProvider
import '../screens/settings_screen.dart'; // For DebugLogView, SettingsScreen

import 'package:uuid/uuid.dart';


// --------------------
// File Explorer Providers
// --------------------

// New provider for current directory contents in file explorer (scoped to ProjectExplorerView)
final currentProjectDirectoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String>((ref, uri) async {
  final handler = ref.read(fileHandlerProvider);
  final project = ref.watch(sessionProvider.select((s) => s.currentProject));
  // Ensure the URI is within the current project's root for security/consistency
  if (project == null || !uri.startsWith(project.rootUri)) {
    return [];
  }
  // Get the includeHidden status from the current project's view mode if applicable
  final includeHidden = project.fileExplorerViewMode == FileExplorerViewMode.showAllFiles;

  return handler.listDirectory(uri, includeHidden: includeHidden);
});


// NEW: Provider for total file/folder counts in the current project
final projectStatsProvider = FutureProvider.autoDispose<({int files, int folders})>((ref) async {
  final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));
  if (currentProject == null) return (files: 0, folders: 0);

  final fileHandler = ref.read(fileHandlerProvider);
  int totalFiles = 0;
  int totalFolders = 0;

  Future<void> countContents(String uri) async {
    // Note: Counting hidden folders for total stats, but listDirectory filters by default
    final contents = await fileHandler.listDirectory(uri, includeHidden: true);
    for (final item in contents) {
      if (item.isDirectory) {
        totalFolders++;
        // Avoid infinite recursion or counting .machine folder for stats
        if (item.name != '.machine') { // Assuming .machine is the specific hidden folder
          await countContents(item.uri);
        }
      } else {
        totalFiles++;
      }
    }
  }

  await countContents(currentProject.rootUri);
  return (files: totalFiles, folders: totalFolders);
});

// Helper dialog functions (Moved to top-level private functions for broad access)
Future<String?> _showTextInputDialog(BuildContext context, {required String title, required String labelText, String? initialValue}) {
  TextEditingController controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: labelText),
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(ctx, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('OK')),
      ],
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

void _showSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}


class UnsupportedFileType implements Exception {
  final String uri;
  UnsupportedFileType(this.uri);

  @override
  String toString() => 'Unsupported file type: $uri';
}

class PluginSelectionDialog extends StatelessWidget {
  final List<EditorPlugin> plugins;

  const PluginSelectionDialog({super.key, required this.plugins});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open With'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: plugins.map((plugin) {
            return ListTile(
              leading: plugin.icon,
              title: Text(plugin.name),
              onTap: () => Navigator.pop(context, plugin),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class FileExplorerDrawer extends ConsumerWidget {
  const FileExplorerDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));

    return Drawer(
      child: currentProject == null
          ? const ProjectSelectionScreen()
          : const ProjectExplorerView(),
    );
  }
}


// NEW: Project selection screen widget
class ProjectSelectionScreen extends ConsumerWidget {
  const ProjectSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects = ref.watch(sessionProvider.select((s) => s.knownProjects));
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final fileHandler = ref.read(fileHandlerProvider);

    return Column(
      children: [
        AppBar(
          title: const Text('Open Project'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Open Existing Project
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Open Existing Project'),
                onPressed: () async {
                  // This block always tries to close the drawer in its finally block.
                  try {
                    final pickedDir = await fileHandler.pickDirectory();
                    if (pickedDir != null) {
                      final existingProject = knownProjects.firstWhereOrNull((p) => p.rootUri == pickedDir.uri);
                      if (existingProject != null) {
                          await sessionNotifier.openProject(existingProject.id);
                      } else {
                          await sessionNotifier.createProject(pickedDir.uri, pickedDir.name);
                      }
                    }
                  } catch (e, st) {
                    ref.read(logProvider.notifier).add('Error opening project: $e\n$st');
                    _showSnackbar(context, 'Error opening project: ${e.toString().split(':')[0]}');
                  } finally {
                    Navigator.pop(context); // Crucial: Pop the dialog/drawer regardless of success/fail
                  }
                },
              ),
              const SizedBox(height: 16),
              // Create New Project
              ElevatedButton.icon(
                icon: const Icon(Icons.create_new_folder),
                label: const Text('Create New Project'),
                onPressed: () async {
                  try {
                    final parentDir = await fileHandler.pickDirectory();
                    if (parentDir != null) {
                      final newProjectName = await _showTextInputDialog(
                        context,
                        title: 'New Project Name',
                        labelText: 'Project Name',
                        initialValue: 'MyNewProject',
                      );
                      if (newProjectName != null && newProjectName.isNotEmpty) {
                        await sessionNotifier.createProject(parentDir.uri, newProjectName);
                      }
                    }
                  } catch (e, st) {
                    ref.read(logProvider.notifier).add('Error creating project: $e\n$st');
                    _showSnackbar(context, 'Error creating project: ${e.toString().split(':')[0]}');
                  } finally {
                    Navigator.pop(context); // Always pop the drawer
                  }
                },
              ),
              const Divider(height: 32),
              Text('Recent Projects', style: Theme.of(context).textTheme.titleMedium),
              if (knownProjects.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text('No recent projects. Open or create one!'),
                ),
              ...knownProjects.map((projectMetadata) {
                return ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(projectMetadata.name),
                  subtitle: Text(projectMetadata.rootUri, overflow: TextOverflow.ellipsis),
                  onTap: () async {
                    try {
                      await sessionNotifier.openProject(projectMetadata.id);
                    } catch (e, st) {
                      ref.read(logProvider.notifier).add('Failed to open recent project: $e\n$st');
                      _showSnackbar(context, 'Failed to open project: ${projectMetadata.name}. It might have moved or permissions are lost.');
                    } finally {
                      Navigator.pop(context); // Always pop the drawer
                    }
                  },
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }
}

// NEW: Main project explorer view widget
class ProjectExplorerView extends ConsumerWidget {
  const ProjectExplorerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));
    if (currentProject == null) {
      return const Center(child: Text('No project selected.'));
    }

    final statsAsync = ref.watch(projectStatsProvider);

    return Column(
      children: [
        // Top Header Area (Mimicking Screenshot)
        Container(
          color: Theme.of(context).appBarTheme.backgroundColor,
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ProjectDropdown(currentProject: currentProject),
                  IconButton(
                    icon: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                ],
              ),
              // Project Stats
              statsAsync.when(
                data: (stats) => Text(
                  '${stats.files} files, ${stats.folders} folders',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
                ),
                loading: () => Text(
                  'Loading stats...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
                ),
                error: (err, stack) => Text(
                  'Error loading stats',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Files',
                        prefixIcon: Icon(Icons.search),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  FileExplorerModeDropdown(currentMode: currentProject.fileExplorerViewMode),
                ],
              ),
            ],
          ),
        ),
        // Main File Tree Body
        Expanded(
          child: _DirectoryView( // Corrected: Direct constructor call
            directory: currentProject.rootUri,
            projectRootUri: currentProject.rootUri,
            expandedFolders: currentProject.expandedFolders,
          ),
        ),
        // Bottom File Operations Bar
        _FileOperationsFooter(projectRootUri: currentProject.rootUri), // Corrected: Direct constructor call
      ],
    );
  }

  String _getModeDisplayName(FileExplorerViewMode mode) {
    switch (mode) {
      case FileExplorerViewMode.sortByNameAsc: return 'Files (A-Z)';
      case FileExplorerViewMode.sortByNameDesc: return 'Files (Z-A)';
      case FileExplorerViewMode.sortByDateModified: return 'Files (Date)';
      case FileExplorerViewMode.showAllFiles: return 'All Files';
      case FileExplorerViewMode.showOnlyCode: return 'Code Files';
    }
  }
}

// NEW: Project Name Dropdown Widget
class ProjectDropdown extends ConsumerWidget {
  final Project currentProject;
  const ProjectDropdown({super.key, required this.currentProject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects = ref.watch(sessionProvider.select((s) => s.knownProjects));
    final sessionNotifier = ref.read(sessionProvider.notifier);

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: currentProject.id,
        onChanged: (projectId) {
          if (projectId == '_manage_projects') {
            Navigator.pop(context);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => FractionallySizedBox(
                heightFactor: 0.9,
                child: ManageProjectsScreen(), // Corrected: Direct constructor call
              ),
            );
          } else if (projectId != null && projectId != currentProject.id) {
            sessionNotifier.openProject(projectId);
          }
        },
        items: [
          ...knownProjects.map((proj) => DropdownMenuItem(
            value: proj.id,
            child: Text(proj.name, style: Theme.of(context).textTheme.titleLarge),
          )).toList(),
          const DropdownMenuItem(
            value: '_manage_projects',
            child: Text('Manage Projects...', style: TextStyle(fontStyle: FontStyle.italic)),
          ),
        ],
        selectedItemBuilder: (BuildContext context) {
          return knownProjects.map<Widget>((proj) {
            return Row(
              children: [
                Text(proj.name, style: Theme.of(context).textTheme.titleLarge),
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

// NEW: File Explorer Mode Dropdown
class FileExplorerModeDropdown extends ConsumerWidget {
  final FileExplorerViewMode currentMode;
  const FileExplorerModeDropdown({super.key, required this.currentMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionNotifier = ref.read(sessionProvider.notifier);
    return DropdownButtonHideUnderline(
      child: DropdownButton<FileExplorerViewMode>(
        value: currentMode,
        onChanged: (mode) {
          if (mode != null) {
            sessionNotifier.updateProjectExplorerMode(mode);
          }
        },
        items: FileExplorerViewMode.values.map((mode) {
          return DropdownMenuItem(
            value: mode,
            child: Text(_getModeDisplayName(mode)),
          );
        }).toList(),
        icon: const Icon(Icons.sort),
        isDense: true,
      ),
    );
  }

  String _getModeDisplayName(FileExplorerViewMode mode) {
    switch (mode) {
      case FileExplorerViewMode.sortByNameAsc:
        return 'Name (A-Z)';
      case FileExplorerViewMode.sortByNameDesc:
        return 'Name (Z-A)';
      case FileExplorerViewMode.sortByDateModified:
        return 'Date Modified';
      case FileExplorerViewMode.showAllFiles:
        return 'All Files';
      case FileExplorerViewMode.showOnlyCode:
        return 'Code Only';
    }
  }
}


// NEW: Manager for generic file explorer context commands
class FileExplorerContextCommands {
  static List<FileContextCommand> getCommands(WidgetRef ref, DocumentFile item) {
    final fileHandler = ref.read(fileHandlerProvider);
    final clipboardContent = ref.watch(clipboardProvider);

    return [
      BaseFileContextCommand(
        id: 'rename',
        label: 'Rename',
        icon: const Icon(Icons.edit),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true,
        executeFor: (ref, item) async {
          final context = ref.context;
          if (context == null) return;
          final newName = await _showTextInputDialog(
            context,
            title: 'Rename ${item.isDirectory ? 'Folder' : 'File'}',
            labelText: 'New Name',
            initialValue: item.name,
          );
          if (newName != null && newName.isNotEmpty && newName != item.name) {
            try {
              final renamedFile = await fileHandler.renameDocumentFile(item, newName);
              // Invalidate the parent directory to refresh the UI
              ref.invalidate(currentProjectDirectoryContentsProvider(_getParentUri(item.uri)));
              ref.invalidate(projectStatsProvider); // Stats might change due to rename
              _showSnackbar(context, 'Renamed ${item.name} to $newName');

              // If the renamed item was the current project's root, update project metadata
              final currentProject = ref.read(sessionProvider).currentProject;
              if (currentProject != null && item.uri == currentProject.rootUri && renamedFile != null) {
                final sessionNotifier = ref.read(sessionProvider.notifier);
                // The SessionNotifier.openProject will update the currentProject in state
                // and also update its metadata in the knownProjects list.
                // We'll call openProject with the current project's ID to trigger this update.
                await sessionNotifier.openProject(currentProject.id); // This will reload with new name/URI
              }

            } catch (e, st) {
              print('Failed to rename: $e\n$st');
              _showSnackbar(context, 'Failed to rename: ${e.toString().split(':')[0]}');
            }
          }
        },
      ),
      BaseFileContextCommand(
        id: 'delete',
        label: 'Delete',
        icon: const Icon(Icons.delete_forever),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true,
        executeFor: (ref, item) async {
          final context = ref.context;
          if (context == null) return;
          final confirmed = await _showConfirmDialog(context,
              title: 'Delete ${item.isDirectory ? 'Folder' : 'File'}?',
              content: 'Are you sure you want to delete "${item.name}"? This cannot be undone.');
          if (confirmed) {
            try {
              // If deleting the current project's root, trigger project deletion flow
              if (item.uri == ref.read(sessionProvider).currentProject?.rootUri) {
                final projectToDeleteId = ref.read(sessionProvider).currentProject!.id;
                await ref.read(sessionProvider.notifier).deleteProject(projectToDeleteId, deleteFolder: true);
              } else {
                // For non-root items, just delete the file/folder
                await fileHandler.deleteDocumentFile(item);
                // Invalidate parent directory to refresh UI
                ref.invalidate(currentProjectDirectoryContentsProvider(_getParentUri(item.uri)));
                ref.invalidate(projectStatsProvider);
                _showSnackbar(context, 'Deleted ${item.name}');
              }
            } catch (e, st) {
              print('Failed to delete: $e\n$st');
              _showSnackbar(context, 'Failed to delete: ${e.toString().split(':')[0]}');
            }
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
          _showSnackbar(ref.context!, 'Cut ${item.name}');
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
          _showSnackbar(ref.context!, 'Copied ${item.name}');
        },
      ),
      BaseFileContextCommand(
        id: 'paste',
        label: 'Paste',
        icon: const Icon(Icons.content_paste),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) {
          return item.isDirectory && clipboardContent != null;
        },
        executeFor: (ref, destinationFolder) async {
          final clipboard = ref.read(clipboardProvider);
          if (clipboard == null) return;

          final context = ref.context;
          if (context == null) return;

          final fileHandler = ref.read(fileHandlerProvider);
          final sourceFile = await fileHandler.getFileMetadata(clipboard.uri);

          if (sourceFile == null) {
            _showSnackbar(context, 'Clipboard item not found!');
            ref.read(clipboardProvider.notifier).state = null;
            return;
          }

          try {
            if (clipboard.operation == ClipboardOperation.copy) {
              await fileHandler.copyDocumentFile(sourceFile, destinationFolder.uri); // Corrected call
            } else { // Cut operation
              await fileHandler.moveDocumentFile(sourceFile, destinationFolder.uri); // Corrected call
            }
            ref.read(clipboardProvider.notifier).state = null;
            ref.invalidate(currentProjectDirectoryContentsProvider(destinationFolder.uri));
            ref.invalidate(projectStatsProvider);
            _showSnackbar(context, 'Pasted ${sourceFile.name}');
          } catch (e, st) {
            print('Failed to paste: $e\n$st');
            _showSnackbar(context, 'Failed to paste: ${e.toString().split(':')[0]}');
          }
        },
      ),
    ];
  }

  // Helper to get parent URI for invalidation. SAF URI parsing is tricky.
  // This needs to correctly go from content://.../document/tree%3Apath%2Fto%2Fchild
  // to content://.../document/tree%3Apath%2Fto
  static String _getParentUri(String uri) {
    try {
      final parsedUri = Uri.parse(uri);
      // Decode the path component to handle '%2F' as actual slashes
      final decodedPath = Uri.decodeComponent(parsedUri.path);
      
      // Look for the last actual path separator
      final lastSlashIndex = decodedPath.lastIndexOf('/');
      if (lastSlashIndex <= 0) { // Handles root like "/primary%3ADOCS" or malformed
        return parsedUri.origin + (parsedUri.path.contains('/tree/') ? parsedUri.path.substring(0, parsedUri.path.indexOf('/tree/') + 5) : parsedUri.path); // Return origin or base tree path
      }

      // Reconstruct the parent path, then encode it back for URI
      final parentDecodedPath = decodedPath.substring(0, lastSlashIndex);
      final parentEncodedPath = Uri.encodeComponent(parentDecodedPath).replaceAll('%2F', '/'); // Re-encode, but keep / as /

      // Reconstruct the full parent URI, preserving scheme, authority, and "tree/document" parts
      final schemeAuthority = '${parsedUri.scheme}://${parsedUri.authority}';
      
      // Find the specific SAF document/tree prefix to preserve it
      final documentPrefixIndex = parsedUri.path.indexOf('/document/');
      final treePrefixIndex = parsedUri.path.indexOf('/tree/');

      if (documentPrefixIndex != -1) {
        // Example: content://.../document/primary%3Apath%2Fto%2Ffile
        // Parent: content://.../document/primary%3Apath%2Fto
        final docPath = parsedUri.path.substring(documentPrefixIndex + '/document/'.length);
        final parentDocPath = docPath.substring(0, docPath.lastIndexOf('%2F')); // Find the last %2F
        return '$schemeAuthority/document/$parentDocPath';
      } else if (treePrefixIndex != -1) {
        // Example: content://.../tree/primary%3Apath%2Fto%2Ffolder (where folder is not the root)
        // Parent: content://.../tree/primary%3Apath%2Fto
        final treePath = parsedUri.path.substring(treePrefixIndex + '/tree/'.length);
        final parentTreePath = treePath.substring(0, treePath.lastIndexOf('%2F'));
        return '$schemeAuthority/tree/$parentTreePath';
      } else {
        // Fallback for URIs that don't match typical SAF patterns (e.g., initial root selection)
        return uri;
      }
    } catch (e) {
      print('Error getting parent URI for $uri: $e');
      return uri; // Return original URI as a safe fallback
    }
  }
}


// NEW: Manage Projects Screen
class ManageProjectsScreen extends ConsumerWidget {
  const ManageProjects({super.key}); // Corrected constructor

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects = ref.watch(sessionProvider.select((s) => s.knownProjects));
    final sessionNotifier = ref.read(sessionProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Projects')),
      body: ListView.builder(
        itemCount: knownProjects.length,
        itemBuilder: (context, index) {
          final project = knownProjects[index];
          final isCurrent = ref.watch(sessionProvider.select((s) => s.currentProject?.id == project.id));
          return ListTile(
            leading: Icon(isCurrent ? Icons.folder_open : Icons.folder),
            title: Text(project.name + (isCurrent ? ' (Current)' : '')),
            subtitle: Text(project.rootUri, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: isCurrent ? null : () async {
                final confirm = await _showConfirmDialog(
                  context,
                  title: 'Delete "${project.name}"?',
                  content: 'This will remove the project from your history. '
                           'Do you also want to delete the folder from your device?',
                );
                if (confirm) {
                  final confirmFolderDelete = await _showConfirmDialog(
                    context,
                    title: 'Confirm Folder Deletion',
                    content: 'This will PERMANENTLY delete the project folder "${project.name}" from your device. This cannot be undone!',
                  );
                  await sessionNotifier.deleteProject(project.id, deleteFolder: confirmFolderDelete);
                }
              },
            ),
            onTap: isCurrent ? null : () async {
              await sessionNotifier.openProject(project.id);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}


// MODIFIED: _FileOperationsFooter to use the new project structure
class _FileOperationsFooter extends ConsumerWidget {
  final String projectRootUri;

  const _FileOperationsFooter({required this.projectRootUri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final fileHandler = ref.read(fileHandlerProvider);
    final clipboardContent = ref.watch(clipboardProvider);

    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Create File
          IconButton(
            icon: Icon(Icons.edit_document, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Create New File',
            onPressed: () async {
              final newFileName = await _showTextInputDialog(
                context,
                title: 'New File Name',
                labelText: 'File Name (e.g., my_script.dart)',
              );
              if (newFileName != null && newFileName.isNotEmpty) {
                try {
                  await fileHandler.createDocumentFile(projectRootUri, newFileName, isDirectory: false);
                  ref.invalidate(currentProjectDirectoryContentsProvider(projectRootUri));
                } catch (e) {
                  ref.read(logProvider.notifier).add('Error creating file: $e');
                }
              }
            },
          ),
          // Create Folder
          IconButton(
            icon: Icon(Icons.create_new_folder, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Create New Folder',
            onPressed: () async {
              final newFolderName = await _showTextInputDialog(
                context,
                title: 'New Folder Name',
                labelText: 'Folder Name',
              );
              if (newFolderName != null && newFolderName.isNotEmpty) {
                try {
                  await fileHandler.createDocumentFile(projectRootUri, newFolderName, isDirectory: true);
                  ref.invalidate(currentProjectDirectoryContentsProvider(projectRootUri));
                } catch (e) {
                  ref.read(logProvider.notifier).add('Error creating folder: $e');
                }
              }
            },
          ),
          // Import File into Project
          IconButton(
            icon: Icon(Icons.file_upload, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Import File',
            onPressed: () async {
              final pickedFile = await fileHandler.pickFile();
              if (pickedFile != null) {
                try {
                  await fileHandler.copyDocumentFile(pickedFile, projectRootUri);
                  ref.invalidate(currentProjectDirectoryContentsProvider(projectRootUri));
                } catch (e) {
                  ref.read(logProvider.notifier).add('Error importing file: $e');
                }
              }
            },
          ),
          // Expand All
          IconButton(
            icon: Icon(Icons.unfold_more, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Expand All Folders',
            onPressed: () => sessionNotifier.toggleAllFolderExpansion(expand: true),
          ),
          // Collapse All
          IconButton(
            icon: Icon(Icons.unfold_less, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Collapse All Folders',
            onPressed: () => sessionNotifier.toggleAllFolderExpansion(expand: false),
          ),
          // Paste (only active if clipboard has content)
          IconButton(
            icon: Icon(Icons.content_paste, color: clipboardContent != null ? Theme.of(context).colorScheme.primary : Colors.grey),
            tooltip: 'Paste',
            onPressed: clipboardContent != null
                ? () async {
                    // Try to paste into the root of the current project
                    // The actual paste logic is also in FileExplorerContextCommands for context menus
                    final pasteCommand = FileExplorerContextCommands.getCommands(ref, DocumentFilePlaceholder(uri: projectRootUri, isDirectory: true))
                                            .firstWhereOrNull((cmd) => cmd.id == 'paste');
                    if (pasteCommand != null && pasteCommand.canExecuteFor(ref, DocumentFilePlaceholder(uri: projectRootUri, isDirectory: true))) {
                      await pasteCommand.executeFor(ref, DocumentFilePlaceholder(uri: projectRootUri, isDirectory: true));
                    } else {
                      print('Paste command not executable for project root.');
                    }
                  }
                : null,
          ),
          // Close Drawer
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close File Explorer',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

// Temporary placeholder for DocumentFile when only URI and isDirectory are known for context menu checks
class DocumentFilePlaceholder implements DocumentFile {
  @override
  final String uri;
  @override
  final bool isDirectory;
  @override
  String get name => '';
  @override
  int get size => 0;
  @override
  DateTime get modifiedDate => DateTime.now();
  @override
  String get mimeType => '';
  DocumentFilePlaceholder({required this.uri, required this.isDirectory});
}

// MODIFIED: _DirectoryView to use project structure and expansion state
class _DirectoryView extends ConsumerWidget {
  final String directory; // Current directory URI
  final String projectRootUri; // Root of the entire project
  final Set<String> expandedFolders; // Set of expanded folder URIs

  const _DirectoryView({
    required this.directory,
    required this.projectRootUri,
    required this.expandedFolders,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(currentProjectDirectoryContentsProvider(directory));
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));

    return contentsAsync.when(
      loading: () => _buildLoadingState(context),
      error: (error, stack) => _buildErrorState(context, error, stack),
      data: (contents) {
        List<DocumentFile> filteredContents = _applyFiltering(contents, currentProject?.fileExplorerViewMode);
        _applySorting(filteredContents, currentProject?.fileExplorerViewMode); // Sort in place

        return ListView.builder(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: filteredContents.length,
          itemBuilder: (context, index) {
            final item = filteredContents[index];
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

  List<DocumentFile> _applyFiltering(List<DocumentFile> contents, FileExplorerViewMode? mode) {
    if (mode == FileExplorerViewMode.showOnlyCode) {
      return contents.where((file) => !file.isDirectory && _isCodeFile(file.name)).toList();
    }
    return contents;
  }

  // This check should use a more robust method, potentially from CodeThemes or a plugin.
  // For now, it's a simple extension check.
  bool _isCodeFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return const {
      'dart', 'js', 'ts', 'py', 'java', 'kt', 'cpp', 'c', 'h', 'html', 'css', 'json', 'xml', 'md', 'sh', 'yaml', 'yml', 'tex'
    }.contains(ext);
  }


  void _applySorting(List<DocumentFile> contents, FileExplorerViewMode? mode) {
    contents.sort((a, b) {
      // Always put directories first
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }

      // Then apply sorting based on mode
      switch (mode) {
        case FileExplorerViewMode.sortByNameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case FileExplorerViewMode.sortByDateModified:
          return b.modifiedDate.compareTo(a.modifiedDate); // Newest first
        case FileExplorerViewMode.sortByNameAsc: // Default
        default:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
  }

  Widget _buildLoadingState(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: const [_DirectoryLoadingTile(depth: 0)],
    );
  }

  Widget _buildErrorState(BuildContext context, Object error, StackTrace stack) {
    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          leading: const Icon(Icons.error, color: Colors.red),
          title: const Text('Error loading directory'),
          subtitle: Text(error.toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// MODIFIED: _DirectoryItem for context menus and proper expansion
class _DirectoryItem extends ConsumerWidget {
  final DocumentFile item;
  final int depth;
  final bool isExpanded;

  const _DirectoryItem({
    required this.item,
    required this.depth,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));

    Widget childWidget;
    if (item.isDirectory) {
      childWidget = ExpansionTile(
        key: ValueKey(item.uri),
        leading: Icon(
          isExpanded ? Icons.folder_open : Icons.folder,
          color: Colors.yellow,
        ),
        title: Text(item.name),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          sessionNotifier.toggleFolderExpansion(item.uri);
        },
        childrenPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
        children: [
          if (isExpanded && currentProject != null)
            _DirectoryView(
              directory: item.uri,
              projectRootUri: currentProject.rootUri,
              expandedFolders: currentProject.expandedFolders,
            ),
        ],
      );
    } else {
      childWidget = ListTile(
        contentPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
        leading: FileTypeIcon(file: item),
        title: Row(
          children: [
            Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis)),
            _FileExtensionTag(file: item),
          ],
        ),
        onTap: () {
          sessionNotifier.openFile(item);
          Navigator.pop(context);
        },
      );
    }

    // Wrap with GestureDetector for long-press context menu
    return GestureDetector(
      onLongPress: () => _showContextMenu(context, ref, item),
      child: childWidget,
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref, DocumentFile item) {
    final List<FileContextCommand> genericCommands =
        FileExplorerContextCommands.getCommands(ref, item);

    final List<FileContextCommand> pluginCommands = [];
    final activePlugins = ref.read(activePluginsProvider);
    for (final plugin in activePlugins) {
      pluginCommands.addAll(plugin.getFileContextMenuCommands(item));
    }

    final List<FileContextCommand> allCommands = [
      ...genericCommands,
      ...pluginCommands,
    ].where((cmd) => cmd.canExecuteFor(ref, item)).toList();

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
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
        );
      },
    );
  }
}

// NEW: Widget for file extension tag (JS, DART etc.)
class _FileExtensionTag extends ConsumerWidget {
  final DocumentFile file;

  const _FileExtensionTag({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (file.isDirectory) return const SizedBox.shrink();

    final ext = file.name.split('.').last.toUpperCase();
    if (ext.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(left: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Text(
        ext,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.orange[300],
        ),
      ),
    );
  }
}


class _FileItem extends StatelessWidget { // This class appears unused based on _DirectoryItem implementation.
  final DocumentFile file;
  final int depth;
  final VoidCallback onTap;

  const _FileItem({
    required this.file,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
      leading: const Icon(Icons.insert_drive_file),
      title: Text(file.name),
      onTap: onTap,
    );
  }
}

// MODIFIED: _DirectoryLoadingTile
class _DirectoryLoadingTile extends StatelessWidget {
  final int depth;

  const _DirectoryLoadingTile({required this.depth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: (depth + 1) * 16.0, top: 8.0, bottom: 8.0),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 16),
          Text('Loading...')
        ],
      ),
    );
  }
}