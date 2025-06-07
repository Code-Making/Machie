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

import 'package:uuid/uuid.dart'; // Add to pubspec.yaml if not already


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
                  try {
                    final pickedDir = await fileHandler.pickDirectory();
                    if (pickedDir != null) {
                      // Check if this picked directory is already a known project
                      final existingProject = knownProjects.firstWhereOrNull((p) => p.rootUri == pickedDir.uri);
                      if (existingProject != null) {
                          await sessionNotifier.openProject(existingProject.id);
                      } else {
                          // If it's a new directory, create a new project entry for it
                          // Note: createProject now handles ID generation internally
                          await sessionNotifier.createProject(pickedDir.uri, pickedDir.name);
                      }
                    }
                  } catch (e, st) {
                    ref.read(logProvider.notifier).add('Error opening project: $e\n$st');
                    _showSnackbar(context, 'Error opening project: ${e.toString().split(':')[0]}');
                  } finally {
                    Navigator.pop(context); // Always try to close drawer
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
                    final parentDir = await fileHandler.pickDirectory(); // Pick parent for new folder
                    if (parentDir != null) {
                      final newProjectName = await _showTextInputDialog(
                        context,
                        title: 'New Project Name',
                        labelText: 'Project Name',
                        initialValue: 'MyNewProject', // Provide a default
                      );
                      if (newProjectName != null && newProjectName.isNotEmpty) {
                        await sessionNotifier.createProject(parentDir.uri, newProjectName);
                      }
                    }
                  } catch (e, st) {
                    ref.read(logProvider.notifier).add('Error creating project: $e\n$st');
                    _showSnackbar(context, 'Error creating project: ${e.toString().split(':')[0]}');
                  } finally {
                    Navigator.pop(context); // Always try to close drawer
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
                      // Optionally, remove the project from knownProjects if it consistently fails to open
                      // await sessionNotifier.deleteProject(projectMetadata.id, deleteFolder: false);
                    } finally {
                      Navigator.pop(context); // Close drawer
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
              // Files/Filter Bar (Mimicking Screenshot)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _getModeDisplayName(currentProject.fileExplorerViewMode),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FileExplorerModeDropdown(currentMode: currentProject.fileExplorerViewMode), // Pass current mode
                ],
              ),
            ],
          ),
        ),

        // Main Directory Tree
        Expanded(
          child: _DirectoryView(
            directory: currentProject.rootUri,
            projectRootUri: currentProject.rootUri,
            expandedFolders: currentProject.expandedFolders,
          ),
        ),

        // Bottom File Operations Bar
        _FileOperationsFooter(projectRootUri: currentProject.rootUri),
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
      default: return 'Files';
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
        value: currentProject.id, // Current project's ID as value
        icon: const Icon(Icons.arrow_drop_down),
        iconSize: 24,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface, // Ensure text color is visible
        ),
        onChanged: (String? newProjectId) async {
          if (newProjectId != null && newProjectId != currentProject.id) {
            if (newProjectId == '_manage_projects') {
              Navigator.pop(context); // Close drawer
              await showModalBottomSheet( // Changed to showModalBottomSheet for better UX
                context: context,
                isScrollControlled: true, // Allow full height
                builder: (ctx) => FractionallySizedBox( // Make it take most of the screen
                  heightFactor: 0.9,
                  child: ManageProjectsScreen(),
                ),
              );
            } else {
              try {
                await sessionNotifier.openProject(newProjectId);
              } catch (e, st) {
                ref.read(logProvider.notifier).add('Failed to switch project: $e\n$st');
                _showSnackbar(context, 'Failed to switch project: ${knownProjects.firstWhereOrNull((p) => p.id == newProjectId)?.name ?? ''}.');
              }
            }
          }
        },
        items: [
          // Other Known Projects (excluding the current one)
          ...knownProjects.where((p) => p.id != currentProject.id).map((p) =>
              DropdownMenuItem(
                value: p.id,
                child: Text(p.name),
              ),
          ),
          // Separator (only if there are other known projects)
          if (knownProjects.length > 1) // Only show divider if there's more than just the current project
            const DropdownMenuItem<String>(
              enabled: false,
              child: Divider(),
            ),
          // Manage Projects Option
          const DropdownMenuItem<String>(
            value: '_manage_projects',
            child: Text('Manage Projects...'),
          ),
        ],
        selectedItemBuilder: (BuildContext context) {
          // This builder must return a list of widgets matching the number of selected items (always 1 for single selection dropdown)
          return [
            Row(
              children: [
                Text(currentProject.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                )),
                const Icon(Icons.arrow_drop_down, color: Colors.white), // Explicit icon for visibility
              ],
            ),
          ];
        },
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
  // getCommands method now requires a ref to be passed from the widget context
  static List<FileContextCommand> getCommands(WidgetRef ref, DocumentFile item) {
    final fileHandler = ref.read(fileHandlerProvider);
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final clipboardContent = ref.watch(clipboardProvider); // Watch clipboard content

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
              // Update state for current project if the root was renamed
              if (item.uri == ref.read(sessionProvider).currentProject?.rootUri) {
                final currentProject = ref.read(sessionProvider).currentProject!;
                final updatedMetadata = currentProject.toMetadata().copyWith(
                  name: newName,
                  rootUri: renamedFile?.uri, // Update root URI if it changed
                );
                // Re-open project to reload its state and update global metadata
                await sessionNotifier.openProject(updatedMetadata.id);
              }
              // Invalidate parent directory to refresh UI for the renamed item
              ref.invalidate(currentProjectDirectoryContentsProvider(_getParentUri(item.uri)));
              ref.invalidate(projectStatsProvider); // Stats might change due to rename
              _showSnackbar(context, 'Renamed ${item.name} to $newName');
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
        canExecuteFor: (ref, item) => true, // Always available
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
                // This calls deleteProject with deleteFolder=true, which includes file system delete
                await sessionNotifier.deleteProject(projectToDeleteId, deleteFolder: true);
              } else {
                // For non-root items, just delete the file/folder
                await fileHandler.deleteDocumentFile(item);
                // Invalidate parent directory to refresh UI
                ref.invalidate(currentProjectDirectoryContentsProvider(_getParentUri(item.uri)));
                ref.invalidate(projectStatsProvider); // Stats might change
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
        canExecuteFor: (ref, item) => true, // Always available
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
        canExecuteFor: (ref, item) => true, // Always available
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
          // Can paste if item is a directory and clipboard has content
          return item.isDirectory && clipboardContent != null;
        },
        executeFor: (ref, destinationFolder) async {
          final clipboard = ref.read(clipboardProvider);
          if (clipboard == null) return;

          final context = ref.context;
          if (context == null) return;

          final fileHandler = ref.read(fileHandlerProvider);
          // Retrieve full metadata of the source file/folder from clipboard URI
          final sourceFile = await fileHandler.getFileMetadata(clipboard.uri);

          if (sourceFile == null) {
            _showSnackbar(context, 'Clipboard item not found!');
            ref.read(clipboardProvider.notifier).state = null; // Clear invalid clipboard
            return;
          }

          try {
            if (clipboard.operation == ClipboardOperation.copy) {
              await fileHandler.copyDocumentFile(sourceFile, destinationFolder.uri, newName: sourceFile.name);
              _showSnackbar(context, 'Copied ${sourceFile.name} to ${destinationFolder.name}');
            } else { // Cut operation
              await fileHandler.moveDocumentFile(sourceFile, destinationFolder.uri, newName: sourceFile.name);
              _showSnackbar(context, 'Moved ${sourceFile.name} to ${destinationFolder.name}');
            }
            ref.read(clipboardProvider.notifier).state = null; // Clear clipboard after paste
            // Invalidate destination folder contents to refresh UI
            ref.invalidate(currentProjectDirectoryContentsProvider(destinationFolder.uri));
            ref.invalidate(projectStatsProvider); // Stats might change
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
      final pathSegments = Uri.decodeComponent(parsedUri.path).split('/');
      
      // Filter out empty segments from splitting, e.g., "" for "///"
      final cleanSegments = pathSegments.where((s) => s.isNotEmpty).toList();

      if (cleanSegments.isEmpty) {
        return uri; // It's already a root-like URI
      }

      // Find the last actual path segment
      final lastSegment = cleanSegments.last;
      
      // Construct parent path by removing the last segment
      String parentPath;
      if (cleanSegments.length == 1) {
          // If only one segment, parent is usually the base SAF tree URI
          // This handles cases like content://.../document/primary%3ADOCS
          // where primary%3ADOCS is the only path segment. The parent is the tree root URI itself.
          final treePrefixIndex = uri.indexOf('/tree/');
          if (treePrefixIndex != -1) {
            // Find the end of the tree URI part: it's before '/document/'
            final documentPartIndex = uri.indexOf('/document/', treePrefixIndex);
            if (documentPartIndex != -1) {
              return uri.substring(0, documentPartIndex);
            }
            return uri.substring(0, treePrefixIndex + '/tree/'.length - 1); // Get to the root of the tree
          }
          return uri; // Fallback
      } else {
          // Remove the last segment and re-encode
          final newPathSegments = cleanSegments.sublist(0, cleanSegments.length - 1);
          parentPath = '/' + newPathSegments.join('/');
      }

      // Reconstruct the full parent URI, ensuring the scheme and authority are preserved
      // And handling the /document/ or /tree/ prefix correctly.
      final baseUri = parsedUri.scheme + '://' + parsedUri.authority;
      final treePart = parsedUri.path.substring(0, parsedUri.path.indexOf(lastSegment)); // Everything before the last segment including '/' or '/document/'

      // Find the base of the content/document/tree path
      final documentStart = parsedUri.path.indexOf('/document/');
      final treeStart = parsedUri.path.indexOf('/tree/');

      if (documentStart != -1) {
        // Path is like /document/primary%3Apath%2Fto%2Ffile
        final docPath = parsedUri.path.substring(documentStart + '/document/'.length);
        final parentDocPath = docPath.substring(0, docPath.lastIndexOf('%2F'));
        return baseUri + '/document/' + parentDocPath;
      } else if (treeStart != -1 && parsedUri.path.length > treeStart + '/tree/'.length) {
        // Path is like /tree/primary%3Apath%2Fto%2Ffolder (itself a tree root)
        // If it's directly a file/folder under the root picked, its parent is the tree URI
        final segmentsAfterTree = parsedUri.path.substring(treeStart + '/tree/'.length).split('%2F');
        if (segmentsAfterTree.length > 1) {
          // If there are multiple segments after tree, it means it's a subfolder/file
          // Reconstruct parent for tree-like paths
          final parentSegments = segmentsAfterTree.sublist(0, segmentsAfterTree.length - 1);
          return baseUri + '/tree/' + parentSegments.join('%2F');
        } else {
          // It's the root picked itself, its parent is effectively system-level or just the base.
          return uri;
        }
      }
      return uri; // Fallback if no specific pattern matched
    } catch (e) {
      print('Error parsing parent URI for $uri: $e');
      return uri; // Return original URI as a safe fallback
    }
  }
}