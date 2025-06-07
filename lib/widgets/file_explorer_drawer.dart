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


// --------------------
// File Explorer Providers
// --------------------

// REMOVED: rootUriProvider (now managed within Project)
// REMOVED: directoryContentsProvider (now managed locally within ProjectExplorerView)

// New provider for current directory contents in file explorer (scoped to ProjectExplorerView)
final currentProjectDirectoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String>((ref, uri) async {
  final handler = ref.read(fileHandlerProvider);
  final project = ref.watch(sessionProvider.select((s) => s.currentProject));
  if (project == null || project.rootUri != uri) {
    // Only list if the URI is within the current project or is the root
    if (!uri.startsWith(project?.rootUri ?? '')) {
      return []; // Don't allow listing arbitrary URIs outside project
    }
  }
  return handler.listDirectory(uri);
});


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
              leading: _getPluginIcon(plugin),
              title: Text(_getPluginName(plugin)),
              onTap: () => Navigator.pop(context, plugin),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _getPluginName(EditorPlugin plugin) {
    // Implement logic to get plugin display name
    return plugin.runtimeType.toString().replaceAll('Plugin', '');
  }

  Widget _getPluginIcon(EditorPlugin plugin) {
    // Implement logic to get plugin icon
    return plugin.icon ?? const Icon(Icons.extension); // Default icon
  }
}

class FileExplorerDrawer extends ConsumerWidget {
  // REMOVED: final DocumentFile? currentDir;

  const FileExplorerDrawer({super.key}); // Removed currentDir parameter

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));

    return Drawer(
      child: currentProject == null
          ? const ProjectSelectionScreen() // NEW: Show project selection when no project is open
          : const ProjectExplorerView(), // NEW: Show project explorer when a project is open
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
                  final pickedDir = await fileHandler.pickDirectory();
                  if (pickedDir != null) {
                    final newProjectId = const Uuid().v4(); // Generate a new ID
                    final projectMetadata = ProjectMetadata(
                      id: newProjectId,
                      name: pickedDir.name,
                      rootUri: pickedDir.uri,
                      lastOpenedDateTime: DateTime.now(),
                    );
                    await sessionNotifier.createProject(pickedDir.uri, pickedDir.name); // Treat as new project initially
                    Navigator.pop(context); // Close drawer
                  }
                },
              ),
              const SizedBox(height: 16),
              // Create New Project
              ElevatedButton.icon(
                icon: const Icon(Icons.create_new_folder),
                label: const Text('Create New Project'),
                onPressed: () async {
                  final parentDir = await fileHandler.pickDirectory();
                  if (parentDir != null) {
                    final newProjectName = await _showTextInputDialog(
                      context,
                      title: 'New Project Name',
                      labelText: 'Project Name',
                    );
                    if (newProjectName != null && newProjectName.isNotEmpty) {
                      await sessionNotifier.createProject(parentDir.uri, newProjectName);
                      Navigator.pop(context); // Close drawer
                    }
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
                    await sessionNotifier.openProject(projectMetadata.id);
                    Navigator.pop(context); // Close drawer
                  },
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  // Helper for text input dialog
  Future<String?> _showTextInputDialog(BuildContext context, {required String title, required String labelText}) {
    TextEditingController controller = TextEditingController();
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
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Create')),
        ],
      ),
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
      return const Center(child: Text('No project selected.')); // Should not happen if this is rendered conditionally
    }

    // Number of files and folders (can be calculated or cached in Project state)
    final fileCountFuture = ref.watch(currentProjectDirectoryContentsProvider(currentProject.rootUri));
    final fileCount = fileCountFuture.when(
      data: (files) => files.where((f) => !f.isDirectory).length,
      loading: () => 0,
      error: (_, __) => 0,
    );
    final folderCount = fileCountFuture.when(
      data: (files) => files.where((f) => f.isDirectory).length,
      loading: () => 0,
      error: (_, __) => 0,
    );

    return Column(
      children: [
        // Top Header
        Container(
          color: Theme.of(context).appBarTheme.backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ProjectDropdown(currentProject: currentProject), // NEW: Project dropdown
                  IconButton(
                    icon: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
                    onPressed: () {
                      Navigator.pop(context); // Close drawer first
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$fileCount files, $folderCount folders',
                style: Theme.of(context).textTheme.bodySmall,
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
                  FileExplorerModeDropdown(currentMode: currentProject.fileExplorerViewMode), // NEW: View Mode dropdown
                ],
              ),
            ],
          ),
        ),
        // Main File Tree Body
        Expanded(
          child: _DirectoryView(
            directory: currentProject.rootUri,
            projectRootUri: currentProject.rootUri,
            expandedFolders: currentProject.expandedFolders,
          ),
        ),
        // Bottom File Operations Bar
        _FileOperationsFooter(projectRootUri: currentProject.rootUri), // MODIFIED: Pass projectRootUri
      ],
    );
  }
}

// NEW: Project Name Dropdown
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
            Navigator.pop(context); // Close drawer
            showModalBottomSheet( // Or navigate to a dedicated screen
              context: context,
              builder: (ctx) => ManageProjectsScreen(), // NEW: ManageProjectsScreen
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
        iconSize: 0, // Hide default dropdown icon as it's part of selectedItemBuilder
        isDense: true,
        // Optional: style the dropdown button itself for consistency with screenshot
        // For instance, by wrapping in a GestureDetector with an explicit icon
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
        icon: const Icon(Icons.sort), // Use sort icon
        isDense: true,
      ),
    );
  }

  String _getModeDisplayName(FileExplorerViewMode mode) {
    switch (mode) {
      case FileExplorerViewMode.sortByNameAsc:
        return 'Sort by Name (A-Z)';
      case FileExplorerViewMode.sortByNameDesc:
        return 'Sort by Name (Z-A)';
      case FileExplorerViewMode.sortByDateModified:
        return 'Sort by Date Modified';
      case FileExplorerViewMode.showAllFiles:
        return 'Show All Files';
      case FileExplorerViewMode.showOnlyCode:
        return 'Show Only Code';
    }
  }
}

// NEW: Manager for generic file explorer context commands
class FileExplorerContextCommands {
  static List<FileContextCommand> getCommands(WidgetRef ref, DocumentFile item) {
    final fileHandler = ref.read(fileHandlerProvider);
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final clipboardContent = ref.watch(clipboardProvider);

    return [
      BaseFileContextCommand(
        id: 'rename',
        label: 'Rename',
        icon: const Icon(Icons.edit),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true, // Always available
        executeFor: (ref, item) async {
          final newName = await _showTextInputDialog(
            ref.context,
            title: 'Rename ${item.isDirectory ? 'Folder' : 'File'}',
            labelText: 'New Name',
            initialValue: item.name,
          );
          if (newName != null && newName.isNotEmpty && newName != item.name) {
            await fileHandler.renameDocumentFile(item, newName);
            ref.invalidate(currentProjectDirectoryContentsProvider(item.uri.split('%2F').sublist(0, item.uri.split('%2F').length - 1).join('%2F'))); // Invalidate parent
          }
        },
      ),
      BaseFileContextCommand(
        id: 'delete',
        label: 'Delete',
        icon: const Icon(Icons.delete),
        sourcePlugin: 'FileExplorer',
        canExecuteFor: (ref, item) => true, // Always available
        executeFor: (ref, item) async {
          final confirm = await _showConfirmDialog(
            ref.context,
            title: 'Delete ${item.name}?',
            content: 'This action cannot be undone.',
          );
          if (confirm) {
            await fileHandler.deleteDocumentFile(item);
            ref.invalidate(currentProjectDirectoryContentsProvider(item.uri.split('%2F').sublist(0, item.uri.split('%2F').length - 1).join('%2F'))); // Invalidate parent
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
        canExecuteFor: (ref, item) => item.isDirectory && clipboardContent != null, // Only paste into folders
        executeFor: (ref, item) async {
          if (clipboardContent == null) return;
          final sourceFile = await fileHandler.getFileMetadata(clipboardContent.uri);
          if (sourceFile == null) {
            print('Clipboard source file not found.');
            ref.read(clipboardProvider.notifier).state = null; // Clear invalid clipboard
            return;
          }

          try {
            if (clipboardContent.operation == ClipboardOperation.copy) {
              await fileHandler.copyDocumentFile(sourceFile, item.uri);
            } else { // Cut operation
              await fileHandler.moveDocumentFile(sourceFile, item.uri);
            }
            ref.read(clipboardProvider.notifier).state = null; // Clear clipboard after paste
            ref.invalidate(currentProjectDirectoryContentsProvider(item.uri)); // Invalidate destination folder
          } catch (e) {
            print('Paste failed: $e');
            ref.read(logProvider.notifier).add('Paste failed: $e');
          }
        },
      ),
    ];
  }

  // Helper for text input dialog
  static Future<String?> _showTextInputDialog(BuildContext context, {required String title, required String labelText, String? initialValue}) {
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

  // Helper for confirmation dialog
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


// NEW: Manage Projects Screen
class ManageProjectsScreen extends ConsumerWidget {
  const ManageProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knownProjects = ref.watch(sessionProvider.select((s) => s.knownProjects));
    final sessionNotifier = ref.read(sessionProvider.notifier);

    return Scaffold( // Use Scaffold for a full-screen bottom sheet or new route
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
              onPressed: () async {
                final confirm = await _showConfirmDialog(
                  context,
                  title: 'Delete "${project.name}"?',
                  content: 'This will remove the project from your history. '
                           'Do you also want to delete the folder from your device?',
                );
                if (confirm) { // User confirmed deletion from history
                  final confirmFolderDelete = await _showConfirmDialog(
                    context,
                    title: 'Confirm Folder Deletion',
                    content: 'This will PERMANENTLY delete the project folder "${project.name}" from your device. This cannot be undone!',
                  );
                  await sessionNotifier.deleteProject(project.id, deleteFolder: confirmFolderDelete);
                }
              },
            ),
            onTap: isCurrent ? null : () async { // Only allow tapping if not current
              await sessionNotifier.openProject(project.id);
              Navigator.pop(context); // Close manage screen after opening
            },
          );
        },
      ),
    );
  }

  // Helper for confirmation dialog (duplicated, ideally centralized)
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


// MODIFIED: _FileOperationsFooter to use the new project structure
class _FileOperationsFooter extends ConsumerWidget {
  final String projectRootUri; // NEW: Pass projectRootUri

  const _FileOperationsFooter({required this.projectRootUri}); // NEW: Constructor

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final fileHandler = ref.read(fileHandlerProvider);
    final clipboardContent = ref.watch(clipboardProvider); // Watch clipboard

    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor, // Match app bar color
      height: 60, // Fixed height for the bar
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Create File
          IconButton(
            icon: Icon(Icons.edit_document, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Create New File',
            onPressed: () async {
              final newFileName = await FileExplorerContextCommands._showTextInputDialog(
                context,
                title: 'New File Name',
                labelText: 'File Name (e.g., my_script.dart)',
              );
              if (newFileName != null && newFileName.isNotEmpty) {
                try {
                  await fileHandler.createDocumentFile(projectRootUri, newFileName, isDirectory: false);
                  ref.invalidate(currentProjectDirectoryContentsProvider(projectRootUri)); // Invalidate to refresh list
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
              final newFolderName = await FileExplorerContextCommands._showTextInputDialog(
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
    // REMOVED: int depth
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch for changes in directory contents based on current project and path
    final contentsAsync = ref.watch(currentProjectDirectoryContentsProvider(directory));
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));

    return contentsAsync.when(
      loading: () => _buildLoadingState(context),
      error: (error, stack) => _buildErrorState(context, error, stack),
      data: (contents) {
        // Apply sorting/filtering based on currentProject.fileExplorerViewMode
        List<DocumentFile> filteredContents = _applyFiltering(contents, currentProject?.fileExplorerViewMode);
        _applySorting(filteredContents, currentProject?.fileExplorerViewMode); // Sort in place

        return ListView.builder(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: filteredContents.length,
          itemBuilder: (context, index) {
            final item = filteredContents[index];
            // Calculate depth based on URI path relative to projectRootUri
            final depth = item.uri.split('%2F').length - projectRootUri.split('%2F').length;

            return _DirectoryItem(
              item: item,
              depth: depth,
              isExpanded: expandedFolders.contains(item.uri), // Pass expansion state
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

  bool _isCodeFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    // This logic should ideally use CodeThemes.languageExtToNameMap.containsKey(ext)
    // but importing CodeThemes here would create a circular dependency.
    // For now, a hardcoded list or passing a predicate from CodeEditorPlugin is needed.
    // For simplicity, just use a common set of code extensions.
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
      children: [_DirectoryLoadingTile(depth: 0)], // Depth might need adjustment
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
  final bool isExpanded; // NEW: Receive expansion state

  const _DirectoryItem({
    required this.item,
    required this.depth,
    required this.isExpanded, // Initialize
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));

    Widget childWidget;
    if (item.isDirectory) {
      childWidget = ExpansionTile(
        key: ValueKey(item.uri), // Key important for ReorderableListView if used
        leading: Icon(
          isExpanded ? Icons.folder_open : Icons.folder,
          color: Colors.yellow,
        ),
        title: Text(item.name),
        initiallyExpanded: isExpanded, // Set initial state
        onExpansionChanged: (expanded) {
          sessionNotifier.toggleFolderExpansion(item.uri); // Update project state
        },
        childrenPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
        children: [
          if (isExpanded) // Only render children if expanded
            _DirectoryView(
              directory: item.uri, // Pass URI for child directory
              projectRootUri: currentProject!.rootUri,
              expandedFolders: currentProject.expandedFolders,
            ),
        ],
      );
    } else {
      childWidget = ListTile(
        contentPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
        leading: FileTypeIcon(file: item), // Uses plugin architecture for icon
        title: Row(
          children: [
            Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis)),
            _FileExtensionTag(file: item), // Optional: JS/Dart tag
          ],
        ),
        onTap: () {
          sessionNotifier.openFile(item);
          Navigator.pop(context); // Close drawer after opening file
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
    // 1. Gather Generic File Explorer Commands
    final List<FileContextCommand> genericCommands =
        FileExplorerContextCommands.getCommands(ref, item);

    // 2. Gather Plugin-Specific Commands
    final List<FileContextCommand> pluginCommands = [];
    final activePlugins = ref.read(activePluginsProvider);
    for (final plugin in activePlugins) {
      pluginCommands.addAll(plugin.getFileContextMenuCommands(item));
    }

    // 3. Combine and filter
    final List<FileContextCommand> allCommands = [
      ...genericCommands,
      ...pluginCommands,
    ].where((cmd) => cmd.canExecuteFor(ref, item)).toList();

    showModalBottomSheet( // Using modal bottom sheet for better mobile UX
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
                  Navigator.pop(ctx); // Close sheet
                  command.executeFor(ref, item); // Execute command
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
    if (file.isDirectory) return const SizedBox.shrink(); // No tag for folders

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





class _FileItem extends StatelessWidget {
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