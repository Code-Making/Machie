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
import '../project/project_models.dart'; // NEW: For ProjectMetadata, Project, FileExplorerViewMode, ClipboardItem, ClipboardOperation, clipboardProvider
import '../screens/settings_screen.dart'; // For DebugLogView, SettingsScreen

import 'package:uuid/uuid.dart'; // Add to pubspec.yaml if not already
session_management.dart'; // For SessionState, SessionNotifier

// --------------------
// File Explorer Providers (Revised/Updated)
// --------------------

// REMOVED: rootUriProvider - now part of Project model within SessionState
// REMOVED: directoryContentsProvider - now handled by _DirectoryView based on current project/path

// NEW: Provider for current directory content (family provider, depends on current project and path)
final currentDirectoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String?>((ref, uri) async {
  final handler = ref.read(fileHandlerProvider);
  // Get the includeHidden status from the current project's view mode if applicable
  final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));
  final includeHidden = currentProject?.fileExplorerViewMode == FileExplorerViewMode.showAllFiles;

  return uri != null ? handler.listDirectory(uri, includeHidden: includeHidden) : [];
});


// NEW: Provider for total file/folder counts in the current project
final projectStatsProvider = FutureProvider.autoDispose<({int files, int folders})>((ref) async {
  final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));
  if (currentProject == null) return (files: 0, folders: 0);

  final fileHandler = ref.read(fileHandlerProvider);
  int totalFiles = 0;
  int totalFolders = 0;

  Future<void> countContents(String uri) async {
    final contents = await fileHandler.listDirectory(uri, includeHidden: true); // Count hidden for total stats
    for (final item in contents) {
      if (item.isDirectory) {
        totalFolders++;
        await countContents(item.uri); // Recursively count sub-folders
      } else {
        totalFiles++;
      }
    }
  }

  await countContents(currentProject.rootUri);
  return (files: totalFiles, folders: totalFolders);
});


// --------------------
// File Explorer Specific Commands
// --------------------

abstract class FileContextCommand extends BaseCommand {
  const FileContextCommand({
    required super.id,
    required super.label,
    required super.icon,
    required super.sourcePlugin,
  }) : super(defaultPosition: CommandPosition.contextMenu); // Force default position

  // New abstract methods for context-specific execution
  bool canExecuteFor(WidgetRef ref, DocumentFile item);
  Future<void> executeFor(WidgetRef ref, DocumentFile item);

  // Override execute to prevent global calls and ensure context-specific usage
  @override
  Future<void> execute(WidgetRef ref) async {
    // This should ideally not be called directly.
    // Context commands are meant for executeFor.
    print('Error: FileContextCommand executed without context.');
  }

  // Override canExecute to prevent global calls and ensure context-specific usage
  @override
  bool canExecute(WidgetRef ref) {
    // This should ideally not be called directly.
    // Context commands are meant for canExecuteFor.
    return false;
  }
}

class BaseFileContextCommand extends FileContextCommand {
  final bool Function(WidgetRef, DocumentFile) _canExecuteFor;
  final Future<void> Function(WidgetRef, DocumentFile) _executeFor;

  const BaseFileContextCommand({
    required super.id,
    required super.label,
    required super.icon,
    required super.sourcePlugin,
    required bool Function(WidgetRef, DocumentFile) canExecuteFor,
    required Future<void> Function(WidgetRef, DocumentFile) executeFor,
  }) : _canExecuteFor = canExecuteFor,
       _executeFor = executeFor;

  @override
  bool canExecuteFor(WidgetRef ref, DocumentFile item) => _canExecuteFor(ref, item);

  @override
  Future<void> executeFor(WidgetRef ref, DocumentFile item) => _executeFor(ref, item);
}


// NEW: Class to define generic file explorer context commands
class FileExplorerContextCommands {
  static List<FileContextCommand> getCommands() {
    return [
      _createFileCommand(
        id: 'file_rename',
        label: 'Rename',
        icon: Icons.edit,
        executeFor: (ref, item) async {
          final context = ref.context;
          if (context == null) return;
          final newName = await _promptForNewName(context, item.name);
          if (newName != null && newName != item.name) {
            final fileHandler = ref.read(fileHandlerProvider);
            try {
              await fileHandler.renameDocumentFile(item, newName);
              // Invalidate current directory contents to refresh UI
              ref.invalidate(currentDirectoryContentsProvider(item.isDirectory ? item.uri : _getParentUri(item.uri)));
              ref.invalidate(projectStatsProvider);
              print('Renamed ${item.name} to $newName');
            } catch (e, st) {
              print('Failed to rename: $e\n$st');
              _showSnackbar(context, 'Failed to rename: $e');
            }
          }
        },
        canExecuteFor: (ref, item) => true, // Can always rename files/folders
      ),
      _createFileCommand(
        id: 'file_delete',
        label: 'Delete',
        icon: Icons.delete_forever,
        executeFor: (ref, item) async {
          final context = ref.context;
          if (context == null) return;
          final confirmed = await _confirmDeletion(context, item.name, item.isDirectory);
          if (confirmed) {
            final fileHandler = ref.read(fileHandlerProvider);
            try {
              await fileHandler.deleteDocumentFile(item);
              // Invalidate current directory contents to refresh UI
              ref.invalidate(currentDirectoryContentsProvider(item.isDirectory ? item.uri : _getParentUri(item.uri)));
              ref.invalidate(projectStatsProvider);
              print('Deleted ${item.name}');
            } catch (e, st) {
              print('Failed to delete: $e\n$st');
              _showSnackbar(context, 'Failed to delete: $e');
            }
          }
        },
        canExecuteFor: (ref, item) => true, // Can always delete files/folders
      ),
      _createFileCommand(
        id: 'file_cut',
        label: 'Cut',
        icon: Icons.content_cut,
        executeFor: (ref, item) async {
          ref.read(clipboardProvider.notifier).state = ClipboardItem(
            uri: item.uri,
            isFolder: item.isDirectory,
            operation: ClipboardOperation.cut,
          );
          print('Cut ${item.name}');
          _showSnackbar(ref.context!, 'Cut ${item.name}');
        },
        canExecuteFor: (ref, item) => true,
      ),
      _createFileCommand(
        id: 'file_copy',
        label: 'Copy',
        icon: Icons.content_copy,
        executeFor: (ref, item) async {
          ref.read(clipboardProvider.notifier).state = ClipboardItem(
            uri: item.uri,
            isFolder: item.isDirectory,
            operation: ClipboardOperation.copy,
          );
          print('Copied ${item.name}');
          _showSnackbar(ref.context!, 'Copied ${item.name}');
        },
        canExecuteFor: (ref, item) => true,
      ),
      _createFileCommand(
        id: 'file_paste',
        label: 'Paste',
        icon: Icons.content_paste,
        // Paste is only enabled on folders when clipboard has content
        canExecuteFor: (ref, item) {
          final clipboard = ref.watch(clipboardProvider);
          return item.isDirectory && clipboard != null;
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
              await fileHandler.copyDocumentFile(sourceFile, destinationFolder.uri);
              _showSnackbar(context, 'Copied ${sourceFile.name} to ${destinationFolder.name}');
            } else { // Cut operation
              await fileHandler.moveDocumentFile(sourceFile, destinationFolder.uri);
              _showSnackbar(context, 'Moved ${sourceFile.name} to ${destinationFolder.name}');
            }
            ref.read(clipboardProvider.notifier).state = null; // Clear clipboard after paste
            // Invalidate destination folder contents to refresh UI
            ref.invalidate(currentDirectoryContentsProvider(destinationFolder.uri));
            ref.invalidate(projectStatsProvider); // Stats might change
            print('Pasted ${sourceFile.name}');
          } catch (e, st) {
            print('Failed to paste: $e\n$st');
            _showSnackbar(context, 'Failed to paste: $e');
          }
        },
      ),
    ];
  }

  static FileContextCommand _createFileCommand({
    required String id,
    required String label,
    required IconData icon,
    required bool Function(WidgetRef, DocumentFile) canExecuteFor,
    required Future<void> Function(WidgetRef, DocumentFile) executeFor,
  }) {
    return BaseFileContextCommand(
      id: id,
      label: label,
      icon: Icon(icon),
      sourcePlugin: 'FileExplorer', // Source plugin for generic commands
      canExecuteFor: canExecuteFor,
      executeFor: executeFor,
    );
  }

  static String _getParentUri(String uri) {
    // Basic way to get parent URI for file invalidation
    final segments = Uri.parse(uri).pathSegments;
    if (segments.length <= 1) return uri; // Root or single-level file/folder
    return Uri.parse(uri).resolve('..').toString();
  }

  static Future<String?> _promptForNewName(BuildContext context, String currentName) async {
    TextEditingController controller = TextEditingController(text: currentName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter New Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _confirmDeletion(BuildContext context, String name, bool isFolder) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${isFolder ? 'Folder' : 'File'}?'),
        content: Text('Are you sure you want to delete "${name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
  }

  static void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class UnsupportedFileType implements Exception {
  final String uri;
  UnsupportedFileType(this.uri);
  @override
  String toString() {
    return 'Unsupported file type: $uri';
  }
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
              leading: plugin.icon, // Use plugin's icon
              title: Text(plugin.name), // Use plugin's name
              onTap: () => Navigator.pop(context, plugin),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class FileExplorerDrawer extends ConsumerWidget {
  final Project? currentProject; // Now takes a Project object
  const FileExplorerDrawer({super.key, this.currentProject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If no project is open, show ProjectSelectionScreen
    if (currentProject == null) {
      return const ProjectSelectionScreen();
    } else {
      // If a project is open, show the ProjectExplorerView
      return ProjectExplorerView(project: currentProject!);
    }
  }
}

// NEW: Project Selection Screen
class ProjectSelectionScreen extends ConsumerWidget {
  const ProjectSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: const Text('No Project Open'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Welcome! Open an existing project or create a new one.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open Existing Project'),
                      onPressed: () async {
                        final pickedDir = await ref.read(fileHandlerProvider).pickDirectory();
                        if (pickedDir != null) {
                          final uuid = Uuid(); // For generating project ID
                          await ref.read(sessionProvider.notifier).createProject(
                            pickedDir.uri,
                            pickedDir.name,
                            id: uuid.v4(), // Generate a new UUID
                          );
                          Navigator.pop(context); // Close drawer
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.create_new_folder),
                      label: const Text('Create New Project'),
                      onPressed: () async {
                        final pickedParentDir = await ref.read(fileHandlerProvider).pickDirectory();
                        if (pickedParentDir != null) {
                          final newProjectName = await _promptForText(
                            context,
                            title: 'New Project Name',
                            labelText: 'Project Name',
                            initialText: 'MyNewProject',
                          );
                          if (newProjectName != null && newProjectName.isNotEmpty) {
                            final uuid = Uuid();
                            await ref.read(sessionProvider.notifier).createProject(
                              pickedParentDir.uri,
                              newProjectName,
                              id: uuid.v4(),
                            );
                            Navigator.pop(context); // Close drawer
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Utility to prompt for text input (like project name)
  static Future<String?> _promptForText(BuildContext context, {String title = '', String labelText = '', String initialText = ''}) async {
    TextEditingController controller = TextEditingController(text: initialText);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: labelText),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// NEW: Project Explorer View (main content when project is open)
class ProjectExplorerView extends ConsumerWidget {
  final Project project;
  const ProjectExplorerView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(projectStatsProvider);
    final fileHandler = ref.read(fileHandlerProvider); // To pick files for import

    return Drawer(
      child: Column(
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
                    // Project Name Dropdown
                    ProjectDropdown(project: project),
                    // Settings Gear Icon
                    IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () {
                        Navigator.pop(context); // Close drawer
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
                        _getModeDisplayName(project.fileExplorerViewMode), // Show current mode name
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.swap_vert), // Sort/Filter icon
                      onPressed: () {
                        // Show menu to change FileExplorerViewMode
                        _showViewModeMenu(context, ref);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Directory Tree
          Expanded(
            child: _DirectoryView(
              directory: project.rootUri,
              // No onOpenFile callback directly here. It's handled inside _DirectoryItem.
              // Instead, _DirectoryView takes the expandedFolders set from the project state.
            ),
          ),

          // Bottom File Operations Bar
          Container(
            color: Theme.of(context).appBarTheme.backgroundColor,
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Create File
                IconButton(
                  icon: const Icon(Icons.edit_note), // More fitting icon for new file
                  tooltip: 'Create New File',
                  onPressed: () async {
                    final newFileName = await FileExplorerContextCommands._promptForNewName(context, 'NewFile.txt');
                    if (newFileName != null && newFileName.isNotEmpty) {
                      try {
                        await fileHandler.createDocumentFile(project.rootUri, newFileName, isDirectory: false, initialContent: '');
                        ref.invalidate(currentDirectoryContentsProvider(project.rootUri)); // Refresh root
                        ref.invalidate(projectStatsProvider);
                        _showSnackbar(context, 'Created $newFileName');
                      } catch (e) {
                        _showSnackbar(context, 'Failed to create file: $e');
                      }
                    }
                  },
                ),
                // Create Folder
                IconButton(
                  icon: const Icon(Icons.create_new_folder),
                  tooltip: 'Create New Folder',
                  onPressed: () async {
                    final newFolderName = await FileExplorerContextCommands._promptForNewName(context, 'NewFolder');
                    if (newFolderName != null && newFolderName.isNotEmpty) {
                      try {
                        await fileHandler.createDocumentFile(project.rootUri, newFolderName, isDirectory: true);
                        ref.invalidate(currentDirectoryContentsProvider(project.rootUri)); // Refresh root
                        ref.invalidate(projectStatsProvider);
                        _showSnackbar(context, 'Created $newFolderName');
                      } catch (e) {
                        _showSnackbar(context, 'Failed to create folder: $e');
                      }
                    }
                  },
                ),
                // Import File
                IconButton(
                  icon: const Icon(Icons.upload_file), // Arrow up icon for import
                  tooltip: 'Import File into Project',
                  onPressed: () async {
                    final pickedFile = await fileHandler.pickFile();
                    if (pickedFile != null) {
                      try {
                        await fileHandler.copyDocumentFile(pickedFile, project.rootUri);
                        ref.invalidate(currentDirectoryContentsProvider(project.rootUri)); // Refresh root
                        ref.invalidate(projectStatsProvider);
                        _showSnackbar(context, 'Imported ${pickedFile.name}');
                      } catch (e) {
                        _showSnackbar(context, 'Failed to import file: $e');
                      }
                    }
                  },
                ),
                // Expand/Collapse All
                IconButton(
                  icon: const Icon(Icons.unfold_more), // A generic icon for expand/collapse all
                  tooltip: 'Toggle All Folders',
                  onPressed: () {
                    ref.read(sessionProvider.notifier).toggleAllFolderExpansion();
                  },
                ),
                // Paste (conditionally enabled)
                Consumer(
                  builder: (context, watch, child) {
                    final clipboardItem = watch.watch(clipboardProvider);
                    final isPasteEnabled = clipboardItem != null;
                    return IconButton(
                      icon: const Icon(Icons.content_paste), // Paste icon
                      tooltip: 'Paste Here',
                      onPressed: isPasteEnabled
                          ? () async {
                        // Directly execute the paste command for the project root
                        final pasteCommand = FileExplorerContextCommands.getCommands().firstWhere((cmd) => cmd.id == 'file_paste');
                        if (pasteCommand.canExecuteFor(ref, await fileHandler.getFileMetadata(project.rootUri) ??
                            // Fallback to a dummy dir if root metadata cannot be retrieved
                            CustomSAFDocumentFile(SafDocumentFile(uri: project.rootUri, name: project.name, isDir: true, length: 0, lastModified: 0))) ) {
                          await pasteCommand.executeFor(ref, await fileHandler.getFileMetadata(project.rootUri) ??
                              CustomSAFDocumentFile(SafDocumentFile(uri: project.rootUri, name: project.name, isDir: true, length: 0, lastModified: 0)));
                        }
                      }
                          : null,
                    );
                  },
                ),

                // Close Drawer
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close Explorer',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getModeDisplayName(FileExplorerViewMode mode) {
    switch (mode) {
      case FileExplorerViewMode.sortByNameAsc: return 'Files (A-Z)';
      case FileExplorerViewMode.sortByNameDesc: return 'Files (Z-A)';
      case FileExplorerViewMode.sortByDateModifiedAsc: return 'Oldest First';
      case FileExplorerViewMode.sortByDateModifiedDesc: return 'Newest First';
      case FileExplorerViewMode.showAllFiles: return 'All Files';
      case FileExplorerViewMode.showOnlyCodeFiles: return 'Code Files';
      default: return 'Files';
    }
  }

  void _showViewModeMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: FileExplorerViewMode.values.map((mode) {
            return ListTile(
              title: Text(_getModeDisplayName(mode)),
              onTap: () {
                ref.read(sessionProvider.notifier).updateProjectExplorerMode(mode);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        );
      },
    );
  }

  // Utility to show snackbar
  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}


// NEW: Project Name Dropdown Widget
class ProjectDropdown extends ConsumerWidget {
  final Project project;
  const ProjectDropdown({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects = ref.watch(sessionProvider.select((s) => s.knownProjects));

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: project.id, // Current project's ID as value
        icon: const Icon(Icons.arrow_drop_down),
        iconSize: 24,
        style: Theme.of(context).textTheme.headlineSmall, // Matches "Notes Personnelles" style
        onChanged: (String? newProjectId) async {
          if (newProjectId != null && newProjectId != project.id) {
            if (newProjectId == 'manage_projects') {
              Navigator.pop(context); // Close drawer
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => const ManageProjectsScreen()),
              );
            } else {
              ref.read(sessionProvider.notifier).openProject(newProjectId);
            }
          }
        },
        items: [
          // Current Project Name
          DropdownMenuItem(
            value: project.id,
            child: Text(project.name),
          ),
          // Separator
          const DropdownMenuItem<String>(
            enabled: false, // Make it non-selectable
            child: Divider(),
          ),
          // Other Known Projects
          ...knownProjects.where((p) => p.id != project.id).map((p) =>
              DropdownMenuItem(
                value: p.id,
                child: Text(p.name),
              ),
          ),
          // Separator
          const DropdownMenuItem<String>(
            enabled: false,
            child: Divider(),
          ),
          // Manage Projects Option
          const DropdownMenuItem<String>(
            value: 'manage_projects',
            child: Text('Manage Projects...'),
          ),
        ],
      ),
    );
  }
}

// NEW: Manage Projects Screen
class ManageProjectsScreen extends ConsumerWidget {
  const ManageProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects = ref.watch(sessionProvider.select((s) => s.knownProjects));
    final currentProjectId = ref.watch(sessionProvider.select((s) => s.currentProject?.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Projects'),
      ),
      body: ListView.builder(
        itemCount: knownProjects.length,
        itemBuilder: (context, index) {
          final project = knownProjects[index];
          final isCurrent = project.id == currentProjectId;
          return ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(project.name + (isCurrent ? ' (Current)' : '')),
            subtitle: Text(project.rootUri),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: isCurrent ? null : () async { // Disable delete if it's the current project
                final confirmed = await FileExplorerContextCommands._confirmDeletion(context, project.name, true); // Treat as folder
                if (confirmed) {
                  ref.read(sessionProvider.notifier).deleteProject(project.id, deleteFolder: false); // Just remove from history
                  // Optionally add another dialog to ask "also delete files on disk?"
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${project.name} removed from history.')));
                }
              },
            ),
            onTap: isCurrent ? null : () {
              ref.read(sessionProvider.notifier).openProject(project.id);
              Navigator.pop(context); // Pop ManageProjectsScreen
              Navigator.pop(context); // Pop FileExplorerDrawer
            },
          );
        },
      ),
    );
  }
}


// --------------------
// Directory View (Updated to use Project state)
// --------------------

class _DirectoryView extends ConsumerWidget {
  final String directory; // This is now a URI
  // REMOVED: final Function(DocumentFile) onOpenFile; - Handled internally by _DirectoryItem

  const _DirectoryView({
    required this.directory,
    super.key, // Add key to support auto-scrolling
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the current project to get expanded folders and view mode
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));
    final expandedFolders = currentProject?.expandedFolders ?? {};
    final viewMode = currentProject?.fileExplorerViewMode ?? FileExplorerViewMode.sortByNameAsc;

    final contentsAsync = ref.watch(currentDirectoryContentsProvider(directory));

    return contentsAsync.when(
      loading: () => _buildLoadingState(),
      error: (error, _) => _buildErrorState(error), // Pass error object
      data: (contents) => _buildDirectoryList(contents, expandedFolders, viewMode, ref), // Pass viewMode and ref
    );
  }

  Widget _buildDirectoryList(List<DocumentFile> contents, Set<String> expandedFolders, FileExplorerViewMode viewMode, WidgetRef ref) {
    // Apply sorting/filtering based on viewMode
    List<DocumentFile> sortedContents = List.from(contents);
    switch (viewMode) {
      case FileExplorerViewMode.sortByNameAsc:
        sortedContents.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case FileExplorerViewMode.sortByNameDesc:
        sortedContents.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case FileExplorerViewMode.sortByDateModifiedAsc:
        sortedContents.sort((a, b) => a.modifiedDate.compareTo(b.modifiedDate));
        break;
      case FileExplorerViewMode.sortByDateModifiedDesc:
        sortedContents.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
        break;
      case FileExplorerViewMode.showOnlyCodeFiles:
        sortedContents = sortedContents.where((f) => !f.isDirectory && ref.read(pluginRegistryProvider).any((p) => p.supportsFile(f))).toList();
        break;
      case FileExplorerViewMode.showAllFiles:
      // Handled by includeHidden in currentDirectoryContentsProvider, no further filtering here
        break;
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: sortedContents.length,
      itemBuilder:
          (context, index) => _DirectoryItem(
            item: sortedContents[index],
            isExpanded: expandedFolders.contains(sortedContents[index].uri),
          ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      shrinkWrap: true,
      children: const [_DirectoryLoadingTile()],
    );
  }

  Widget _buildErrorState(Object error) {
    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          leading: const Icon(Icons.error, color: Colors.red),
          title: const Text('Error loading directory'),
          subtitle: Text(error.toString()),
        ),
      ],
    );
  }
}

class _DirectoryItem extends ConsumerWidget {
  final DocumentFile item;
  final bool isExpanded; // NEW: Pass expanded state
  final int depth; // Retain depth for visual indentation

  const _DirectoryItem({
    required this.item,
    required this.isExpanded,
    this.depth = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Common padding for both files and folders
    final itemPadding = EdgeInsets.only(left: (depth * 16.0) + 8.0); // Base padding + indentation

    // Gesture detector for long press (context menu)
    return GestureDetector(
      onLongPressStart: (details) {
        _showContextMenu(context, ref, item, details.globalPosition);
      },
      child: item.isDirectory
          ? _DirectoryTile(
              file: item,
              isExpanded: isExpanded,
              onTap: () => ref.read(sessionProvider.notifier).toggleFolderExpansion(item.uri),
              depth: depth,
            )
          : _FileTile(
              file: item,
              onTap: () => ref.read(sessionProvider.notifier).openFile(item),
              depth: depth,
            ),
    );
  }

  // Context Menu logic moved into a helper function
  void _showContextMenu(BuildContext context, WidgetRef ref, DocumentFile item, Offset position) async {
    final List<PopupMenuEntry<FileContextCommand>> menuItems = [];

    // 1. Add Generic File Explorer Commands
    for (final cmd in FileExplorerContextCommands.getCommands()) {
      if (cmd.canExecuteFor(ref, item)) {
        menuItems.add(
          PopupMenuItem<FileContextCommand>(
            value: cmd,
            child: Row(
              children: [
                cmd.icon,
                const SizedBox(width: 8),
                Text(cmd.label),
              ],
            ),
          ),
        );
      }
    }

    // 2. Add Plugin-Specific Commands
    final activePlugins = ref.read(activePluginsProvider);
    for (final plugin in activePlugins) {
      final pluginCommands = plugin.getFileContextMenuCommands(item);
      for (final cmd in pluginCommands) {
        if (cmd.canExecuteFor(ref, item)) {
          menuItems.add(
            PopupMenuItem<FileContextCommand>(
              value: cmd,
              child: Row(
                children: [
                  cmd.icon,
                  const SizedBox(width: 8),
                  Text(cmd.label),
                ],
              ),
            ),
          );
        }
      }
    }

    if (menuItems.isEmpty) return; // No commands available

    final selectedCommand = await showMenu<FileContextCommand>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40), // Position from tap
        Offset.zero & MediaQuery.of(context).size, // Bounding box
      ),
      items: menuItems,
    );

    if (selectedCommand != null) {
      await selectedCommand.executeFor(ref, item);
    }
  }
}

class _DirectoryTile extends ConsumerWidget {
  final DocumentFile file;
  final bool isExpanded;
  final VoidCallback onTap;
  final int depth;

  const _DirectoryTile({
    required this.file,
    required this.isExpanded,
    required this.onTap,
    required this.depth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: (depth * 16.0) + 8.0),
          leading: Icon(
            isExpanded ? Icons.folder_open : Icons.folder,
            color: Colors.yellow[700],
          ),
          title: Text(file.name),
          trailing: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
          onTap: onTap,
        ),
        if (isExpanded)
          // Recursively build _DirectoryView for expanded folders
          _DirectoryView(
            directory: file.uri,
            key: ValueKey(file.uri), // Key important for list changes
          ),
      ],
    );
  }
}

class _FileTile extends ConsumerWidget {
  final DocumentFile file;
  final VoidCallback onTap;
  final int depth;

  const _FileTile({
    required this.file,
    required this.onTap,
    required this.depth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: (depth * 16.0) + 8.0),
      leading: FileTypeIcon(file: file), // Uses plugin architecture for icon
      title: Text(file.name),
      onTap: onTap,
    );
  }
}

class _DirectoryLoadingTile extends StatelessWidget {
  final int depth; // Add depth for consistent indentation

  const _DirectoryLoadingTile({this.depth = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: (depth * 16.0) + 8.0),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}