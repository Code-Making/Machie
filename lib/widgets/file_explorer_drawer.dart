// lib/widgets/file_explorer_drawer.dart

import 'dart:math'; // For max() in utility functions

import 'package:collection/collection.dart'; // For firstWhereOrNull
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart'; // For CodeLineEditingController (used in context menu logic)

import '../file_system/file_handler.dart'; // For DocumentFile, FileHandler
import '../main.dart'; // For sessionProvider, fileHandlerProvider, logProvider
import '../plugins/code_editor/code_editor_plugin.dart'; // For CodeEditorPlugin, BracketHighlightState, CodeThemes
import '../plugins/plugin_architecture.dart'; // For EditorPlugin, activePluginsProvider, Command, FileContextCommand, BaseFileContextCommand, settingsProvider
import '../project/project_models.dart'; // For Project, ProjectMetadata, FileExplorerViewMode, ClipboardItem, ClipboardOperation, clipboardProvider
import '../session/session_management.dart'; // For SessionState, SessionNotifier, EditorTab
import '../screens/settings_screen.dart'; // For SettingsScreen

// --------------------
// File Explorer Providers
// --------------------

// This will now track the current project's root URI based on sessionProvider.currentProject
// It's effectively derived state, not an independent mutable state.
// We keep it as a provider for `directoryContentsProvider`'s family parameter.
final _currentProjectRootUriProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider.select((s) => s.currentProject?.rootUri));
});

// The list of directory contents for the currently viewed folder in the explorer.
// This is now based on the `_currentProjectRootUriProvider` which is reacted to by `sessionProvider`.
final directoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String?>((ref, uri) async {
  final handler = ref.read(fileHandlerProvider);
  final targetUri = uri; // uri parameter is the specific folder to list
  // No longer gets persisted root URI from handler here, that's session's job
  return targetUri != null
      ? await handler.listDirectory(targetUri)
      : []; // Return empty if no URI
});

// Provider for the currently visible root of the file explorer tree.
// This is typically the current project's root, but could be changed later for sub-views.
final fileExplorerCurrentViewRootProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider.select((s) => s.currentProject?.rootUri));
});

// Provides access to project-specific stats (files/folders count)
final projectStatsProvider = Provider.autoDispose<({int files, int folders})>((ref) {
  final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));
  return (files: currentProject?.filesCount ?? 0, folders: currentProject?.foldersCount ?? 0);
});

// Helper to determine if a folder is expanded based on the current project state
final _isFolderExpandedProvider = Provider.family<bool, String>((ref, folderUri) {
  final expandedFolders = ref.watch(sessionProvider.select((s) => s.currentProject?.expandedFolders));
  return expandedFolders?.contains(folderUri) ?? false;
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
      // Make the drawer full width
      width: MediaQuery.of(context).size.width,
      child: currentProject == null
          ? const ProjectSelectionScreen()
          : const ProjectExplorerView(),
    );
  }
}

/// Widget displayed when no project is open, prompting selection/creation.
class ProjectSelectionScreen extends ConsumerWidget {
  const ProjectSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('No Project Open'),
        automaticallyImplyLeading: false, // Hide back button for drawer
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Open or create a new project to get started!'),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Existing Project'),
              onPressed: () async {
                final pickedDir = await ref.read(fileHandlerProvider).pickDirectory();
                if (pickedDir != null) {
                  // Generate a simple project name from the folder name
                  final projectName = pickedDir.name;
                  // Use a UUID for the ID to ensure uniqueness
                  final projectId = pickedDir.uri; // Using URI as ID for simplicity
                  await ref.read(sessionProvider.notifier).createProject(pickedDir.uri, projectName);
                  Navigator.pop(context); // Close drawer
                }
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.create_new_folder),
              label: const Text('Create New Project'),
              onPressed: () async {
                // First, pick a parent directory
                final parentDir = await ref.read(fileHandlerProvider).pickDirectory();
                if (parentDir == null) return;

                // Then, ask for a new project name
                final newProjectName = await _showTextInputDialog(
                  context,
                  title: 'New Project Name',
                  labelText: 'Project Name',
                  hintText: 'My Awesome Project',
                );

                if (newProjectName != null && newProjectName.isNotEmpty) {
                  // Attempt to create the project folder and associated project data
                  await ref.read(sessionProvider.notifier).createProject(parentDir.uri, newProjectName);
                  Navigator.pop(context); // Close drawer
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showTextInputDialog(BuildContext context, {required String title, required String labelText, String? hintText}) {
    TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: labelText, hintText: hintText),
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('Create'),
              onPressed: () => Navigator.pop(context, controller.text),
            ),
          ],
        );
      },
    );
  }
}

/// Displays the active project's file structure and operations.
class ProjectExplorerView extends ConsumerWidget {
  const ProjectExplorerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));
    final projectStats = ref.watch(projectStatsProvider);
    final fileHandler = ref.read(fileHandlerProvider);
    final clipboardItem = ref.watch(clipboardProvider);

    if (currentProject == null) {
      return const ProjectSelectionScreen(); // Should not happen if ProjectExplorerView is shown
    }

    // Determine if paste button should be enabled
    final canPaste = clipboardItem != null;

    return Column(
      children: [
        // Top Header Section (mimics screenshot)
        SafeArea( // Use SafeArea to avoid overlap with status bar
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 8.0, 8.0), // Adjust padding for visual alignment
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Project Name Dropdown
                    ProjectDropdown(currentProject: currentProject),
                    // Settings Gear Icon
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.grey),
                      onPressed: () => Navigator.pushNamed(context, '/settings'),
                    ),
                  ],
                ),
                // Project Stats
                Text(
                  '${projectStats.files} files, ${projectStats.folders} folders',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                // Search/Filter Bar
                Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      // View Mode Dropdown
                      child: FileExplorerModeDropdown(currentProject: currentProject),
                    ),
                    const SizedBox(width: 8),
                    // Filter/Sort Icon (right side of "Sort by Name (A-Z)")
                    IconButton(
                      icon: Icon(currentProject.fileExplorerViewMode.icon, color: Colors.grey),
                      onPressed: () => _showViewModeMenu(context, ref), // Trigger view mode menu
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Main File Tree Body
        Expanded(
          child: _DirectoryView(
            directoryUri: currentProject.rootUri,
            depth: 0,
            projectExplorerViewMode: currentProject.fileExplorerViewMode,
          ),
        ),

        // Bottom File Operations Bar
        Container(
          height: 56, // Fixed height for bottom bar
          color: Theme.of(context).appBarTheme.backgroundColor, // Match app bar color
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Create File
              IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.deepOrange), // Pencil icon from screenshot
                tooltip: 'Create New File',
                onPressed: () => _showCreateFileDialog(context, ref, currentProject.rootUri),
              ),
              // Create Folder
              IconButton(
                icon: const Icon(Icons.create_new_folder, color: Colors.deepOrange), // Folder + icon from screenshot
                tooltip: 'Create New Folder',
                onPressed: () => _showCreateFolderDialog(context, ref, currentProject.rootUri),
              ),
              // Import File
              IconButton(
                icon: const Icon(Icons.upload_file, color: Colors.deepOrange), // Arrow up icon from screenshot
                tooltip: 'Import File into Project',
                onPressed: () => _importFileIntoProject(context, ref, currentProject.rootUri),
              ),
              // Toggle All Expansion
              /*IconButton(
                icon: const Icon(Icons.unfold_more, color: Colors.deepOrange), // Double arrow icon from screenshot
                tooltip: 'Expand/Collapse All Folders',
                onPressed: () => ref.read(sessionProvider.notifier).toggleAllFolderExpansion(),
              ),*/
              // Paste
              IconButton(
                icon: const Icon(Icons.content_paste, color: Colors.deepOrange), // Clipboard icon from screenshot
                tooltip: canPaste ? 'Paste ${clipboardItem!.name}' : 'Nothing to paste',
                onPressed: canPaste ? () => _handlePaste(context, ref, currentProject.rootUri, clipboardItem!) : null,
              ),
              // Close Drawer (X icon from screenshot)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.deepOrange),
                tooltip: 'Close Explorer',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Helper methods for UI operations ---

  Future<String?> _showTextInputDialog(BuildContext context, {required String title, required String labelText, String? hintText}) {
    TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: labelText, hintText: hintText),
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('Create'), // Or 'Rename' etc.
              onPressed: () => Navigator.pop(context, controller.text),
            ),
          ],
        );
      },
    );
  }

  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showCreateFileDialog(BuildContext context, WidgetRef ref, String parentUri) async {
    final fileName = await _showTextInputDialog(
      context,
      title: 'Create New File',
      labelText: 'File Name',
      hintText: 'new_file.txt',
    );
    if (fileName != null && fileName.isNotEmpty) {
      try {
        await ref.read(fileHandlerProvider).createDocumentFile(parentUri, fileName, isDirectory: false, initialContent: '');
        ref.invalidate(directoryContentsProvider(parentUri)); // Invalidate to refresh list
        ref.read(sessionProvider.notifier).updateProjectCounts(); // Update project counts
        _showSnackbar(context, 'File "$fileName" created.');
      } catch (e, st) {
        _showSnackbar(context, 'Failed to create file: $e');
        ref.read(logProvider.notifier).add('Error creating file: $e\n$st');
      }
    }
  }

  Future<void> _showCreateFolderDialog(BuildContext context, WidgetRef ref, String parentUri) async {
    final folderName = await _showTextInputDialog(
      context,
      title: 'Create New Folder',
      labelText: 'Folder Name',
      hintText: 'New Folder',
    );
    if (folderName != null && folderName.isNotEmpty) {
      try {
        await ref.read(fileHandlerProvider).createDocumentFile(parentUri, folderName, isDirectory: true);
        ref.invalidate(directoryContentsProvider(parentUri)); // Invalidate to refresh list
        ref.read(sessionProvider.notifier).updateProjectCounts(); // Update project counts
        _showSnackbar(context, 'Folder "$folderName" created.');
      } catch (e, st) {
        _showSnackbar(context, 'Failed to create folder: $e');
        ref.read(logProvider.notifier).add('Error creating folder: $e\n$st');
      }
    }
  }

  Future<void> _importFileIntoProject(BuildContext context, WidgetRef ref, String projectRootUri) async {
    final pickedFile = await ref.read(fileHandlerProvider).pickFile();
    if (pickedFile != null) {
      try {
        await ref.read(fileHandlerProvider).copyDocumentFile(pickedFile, projectRootUri);
        ref.invalidate(directoryContentsProvider(projectRootUri)); // Refresh root
        ref.read(sessionProvider.notifier).updateProjectCounts(); // Update project counts
        _showSnackbar(context, 'File "${pickedFile.name}" imported.');
      } catch (e, st) {
        _showSnackbar(context, 'Failed to import file: $e');
        ref.read(logProvider.notifier).add('Error importing file: $e\n$st');
      }
    }
  }

  Future<void> _handlePaste(BuildContext context, WidgetRef ref, String currentProjectRootUri, ClipboardItem item) async {
    final fileHandler = ref.read(fileHandlerProvider);
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final isCut = item.operation == ClipboardOperation.cut;
    final opText = isCut ? 'Moving' : 'Copying';

    try {
      if (isCut) {
        await fileHandler.moveDocumentFile(
          await fileHandler.getFileMetadata(item.uri)!, // Get fresh metadata
          currentProjectRootUri,
        );
      } else {
        await fileHandler.copyDocumentFile(
          await fileHandler.getFileMetadata(item.uri)!,
          currentProjectRootUri,
        );
      }
      ref.read(clipboardProvider.notifier).state = null; // Clear clipboard
      ref.invalidate(directoryContentsProvider(currentProjectRootUri)); // Refresh root
      sessionNotifier.updateProjectCounts(); // Update counts
      _showSnackbar(context, '$opText "${item.name}" completed.');
    } catch (e, st) {
      _showSnackbar(context, 'Failed to $opText "${item.name}": $e');
      ref.read(logProvider.notifier).add('Error $opText: $e\n$st');
    }
  }

  void _showViewModeMenu(BuildContext context, WidgetRef ref) {
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final currentMode = ref.read(sessionProvider.select((s) => s.currentProject?.fileExplorerViewMode));

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 100, // Roughly align to the right
        120, // Position below the header
        0,
        0,
      ),
      items: FileExplorerViewMode.values.map((mode) {
        return PopupMenuItem<FileExplorerViewMode>(
          value: mode,
          child: Row(
            children: [
              Icon(mode.icon),
              const SizedBox(width: 8),
              Text(mode.label),
              if (mode == currentMode) const Icon(Icons.check, size: 16), // Checkmark for active mode
            ],
          ),
        );
      }).toList(),
    ).then((selectedMode) {
      if (selectedMode != null) {
        sessionNotifier.updateProjectExplorerMode(selectedMode);
      }
    });
  }
}

/// Dropdown for selecting the current project.
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
        icon: const Icon(Icons.arrow_drop_down, color: Colors.white), // Screenshot uses a chevron-down
        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
        items: [
          ...knownProjects.map((projectMetadata) {
            return DropdownMenuItem(
              value: projectMetadata.id,
              child: Text(projectMetadata.name),
            );
          }),
          const DropdownMenuItem(
            value: '_manage_projects_', // Special value to open manager
            child: Text('Manage Projects...'),
          ),
        ],
        onChanged: (value) async {
          if (value == '_manage_projects_') {
            // Close the drawer and navigate to Project Manager
            Navigator.pop(context);
            // Example: Navigator.push(context, MaterialPageRoute(builder: (context) => ManageProjectsScreen()));
            _showSnackbar(context, 'Manage Projects Screen (Not Implemented)'); // Placeholder
          } else if (value != null && value != currentProject.id) {
            await sessionNotifier.openProject(value);
          }
        },
      ),
    );
  }

  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Dropdown for selecting the file explorer view mode (e.g., sort order, filter).
class FileExplorerModeDropdown extends ConsumerWidget {
  final Project currentProject;
  const FileExplorerModeDropdown({super.key, required this.currentProject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = currentProject.fileExplorerViewMode;
    final sessionNotifier = ref.read(sessionProvider.notifier);

    return GestureDetector( // Use GestureDetector to make the text itself clickable
      onTap: () => _showViewModeMenu(context, ref),
      child: Row(
        children: [
          // Icon on left (can be dynamically set by mode)
          // Icon(currentMode.icon, color: Colors.grey), // Already handled by the IconButton next to it
          // const SizedBox(width: 8),
          Text(
            currentMode.label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showViewModeMenu(BuildContext context, WidgetRef ref) {
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final currentMode = ref.read(sessionProvider.select((s) => s.currentProject?.fileExplorerViewMode));

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 100, // Adjust position
        120, // Adjust position
        0,
        0,
      ),
      items: FileExplorerViewMode.values.map((mode) {
        return PopupMenuItem<FileExplorerViewMode>(
          value: mode,
          child: Row(
            children: [
              Icon(mode.icon),
              const SizedBox(width: 8),
              Text(mode.label),
              if (mode == currentMode) const Icon(Icons.check, size: 16),
            ],
          ),
        );
      }).toList(),
    ).then((selectedMode) {
      if (selectedMode != null) {
        sessionNotifier.updateProjectExplorerMode(selectedMode);
      }
    });
  }
}

/// Recursive widget to display directory contents.
class _DirectoryView extends ConsumerWidget {
  final String directoryUri;
  final int depth;
  final FileExplorerViewMode projectExplorerViewMode;

  const _DirectoryView({
    required this.directoryUri,
    required this.depth,
    required this.projectExplorerViewMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(directoryContentsProvider(directoryUri));
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final fileHandler = ref.read(fileHandlerProvider);
    final isExpanded = ref.watch(_isFolderExpandedProvider(directoryUri));


    return contentsAsync.when(
      loading: () => _buildLoadingState(context),
      error: (error, stack) {
        // Log the error for debugging
        ref.read(logProvider.notifier).add('Error listing directory $directoryUri: $error\n$stack');
        // Handle permission denied specifically
        if (error is PlatformException && error.code == 'PERMISSION_DENIED') {
           return ListTile(
            leading: const Icon(Icons.warning, color: Colors.orange),
            title: const Text('Access Denied'),
            subtitle: Text('Cannot access: ${Uri.parse(directoryUri).pathSegments.last}'),
            trailing: TextButton(
              child: const Text('Grant Access'),
              onPressed: () async {
                // Attempt to re-pick the directory to gain persistent access
                final rePickedDir = await fileHandler.pickDirectory();
                if (rePickedDir != null && rePickedDir.uri == directoryUri) {
                  // If successfully re-picked the same dir, invalidate to refresh
                  ref.invalidate(directoryContentsProvider(directoryUri));
                  _showSnackbar(context, 'Access granted for ${rePickedDir.name}');
                } else {
                  _showSnackbar(context, 'Could not re-grant access. Please re-open project.');
                  // Optionally, close the project if access is critical
                  // sessionNotifier.closeProject();
                }
              },
            ),
          );
        }
        return ListTile(
          leading: const Icon(Icons.error, color: Colors.red),
          title: Text('Error: ${error.toString()}'),
        );
      },
      data: (contents) {
        final sortedContents = _sortAndFilterContents(contents, projectExplorerViewMode);
        
        return Column( // Use Column to manage expansion
          children: [
            if (depth > 0) // Only for expanded folders, not the root view itself
              // This acts as the clickable header for expansion/collapse
              _DirectoryFolderTile(
                file: sortedContents.firstWhere((e) => e.uri == directoryUri), // This assumes the parent directory is listed as part of its own contents, which is unusual.
                                                                                // Typically, _DirectoryView is called *for* a folder, and it lists its *children*.
                                                                                // Let's assume this tile is only rendered for the *parent* folder that got expanded.
                depth: depth - 1, // Correct depth for the parent tile
                isExpanded: isExpanded,
                onTap: () => sessionNotifier.toggleFolderExpansion(directoryUri),
              ),

            // Actual children list
            if (isExpanded || depth == 0) // Render children if expanded, or if it's the root view
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedContents.length,
                itemBuilder: (context, index) {
                  final item = sortedContents[index];
                  // Skip displaying the current folder itself if it was included in contents list
                  if (depth > 0 && item.uri == directoryUri) return const SizedBox.shrink();

                  return _DirectoryItem(
                    item: item,
                    depth: depth,
                    onOpenFile: (file) async {
                      if (!file.isDirectory) {
                        final plugins = ref.read(pluginRegistryProvider);
                        final supportedPlugins = plugins.where((p) => p.supportsFile(file)).toList();

                        if (supportedPlugins.isEmpty) {
                          _showSnackbar(context, 'No available plugins support ${file.name}');
                          return;
                        }

                        if (supportedPlugins.length == 1) {
                          ref.read(sessionProvider.notifier).openFile(file, plugin: supportedPlugins.first);
                        } else {
                          final selectedPlugin = await showDialog<EditorPlugin>(
                            context: context,
                            builder: (context) => PluginSelectionDialog(plugins: supportedPlugins),
                          );
                          if (selectedPlugin != null) {
                            ref.read(sessionProvider.notifier).openFile(file, plugin: selectedPlugin);
                          }
                        }
                        Navigator.pop(context); // Close explorer drawer after opening file
                      } else {
                        sessionNotifier.toggleFolderExpansion(item.uri);
                      }
                    },
                  );
                },
              ),
          ],
        );
      },
    );
  }

  // --- Helpers for _DirectoryView ---
  Widget _buildLoadingState(BuildContext context) {
    // Only show loading indicator if list is empty or it's taking time
    return Padding(
      padding: EdgeInsets.only(left: (depth + 1) * 16.0),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<DocumentFile> _sortAndFilterContents(List<DocumentFile> contents, FileExplorerViewMode mode) {
    // Filter first
    List<DocumentFile> filtered = contents;
    if (mode == FileExplorerViewMode.showOnlyCodeFiles) {
      filtered = contents.where((file) {
        if (file.isDirectory) return true; // Always show folders
        final ext = file.name.split('.').last.toLowerCase();
        return CodeThemes.languageExtToNameMap.containsKey(ext); // Only show files with registered language support
      }).toList();
    }

    // Then sort
    filtered.sort((a, b) {
      // Always put directories before files
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }

      switch (mode) {
        case FileExplorerViewMode.sortByNameAsc:
        case FileExplorerViewMode.showAllFiles: // Default sort for showAllFiles
        case FileExplorerViewMode.showOnlyCodeFiles:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case FileExplorerViewMode.sortByNameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case FileExplorerViewMode.sortByDateModifiedAsc:
          return a.modifiedDate.compareTo(b.modifiedDate);
        case FileExplorerViewMode.sortByDateModifiedDesc:
          return b.modifiedDate.compareTo(a.modifiedDate);
      }
    });
    return filtered;
  }
}

/// A single item (file or folder) in the directory tree.
class _DirectoryItem extends ConsumerWidget {
  final DocumentFile item;
  final int depth;
  final Function(DocumentFile) onOpenFile;

  const _DirectoryItem({
    required this.item,
    required this.depth,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine if folder is expanded (only relevant if item is a directory)
    final isExpanded = ref.watch(_isFolderExpandedProvider(item.uri));

    return Column(
      children: [
        GestureDetector(
          onLongPressStart: (details) => _showFileContextMenu(context, ref, item, details.globalPosition),
          child: ListTile(
            contentPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
            leading: _getFileLeadingIcon(ref),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!item.isDirectory) // Show extension tag only for files
                  _FileExtensionTag(fileName: item.name),
              ],
            ),
            trailing: item.isDirectory
                ? Icon(
                    isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    color: Colors.grey,
                  )
                : null,
            onTap: () => onOpenFile(item),
          ),
        ),
        if (item.isDirectory && isExpanded)
          _DirectoryView(
            directoryUri: item.uri,
            depth: depth + 1,
            projectExplorerViewMode: ref.watch(sessionProvider.select((s) => s.currentProject!.fileExplorerViewMode)),
          ),
      ],
    );
  }

  Widget _getFileLeadingIcon(WidgetRef ref) {
    if (item.isDirectory) {
      return Icon(Icons.folder, color: Colors.yellow[700]);
    } else {
      return ref.watch(pluginRegistryProvider).firstWhereOrNull((p) => p.supportsFile(item))?.icon ??
          const Icon(Icons.insert_drive_file);
    }
  }

  Future<void> _showFileContextMenu(BuildContext context, WidgetRef ref, DocumentFile file, Offset globalPosition) async {
    final fileHandler = ref.read(fileHandlerProvider);
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final clipboard = ref.read(clipboardProvider);
    final clipboardNotifier = ref.read(clipboardProvider.notifier);
    final projectRootUri = ref.read(sessionProvider.select((s) => s.currentProject?.rootUri))!;

    // 1. Generic File Explorer Commands
    final List<FileContextCommand> genericCommands = [
      RenameFileContextCommand(),
      DeleteFileContextCommand(),
      CopyFileContextCommand(),
      CutFileContextCommand(),
      if (clipboard != null && file.isDirectory) PasteFileContextCommand(), // Paste only on folders
    ];

    // 2. Plugin-Specific Commands
    final List<FileContextCommand> pluginCommands = ref.read(activePluginsProvider)
        .expand((plugin) => plugin.getFileContextMenuCommands(file))
        .toList();

    // Combine and filter commands
    final List<FileContextCommand> allCommands = [...genericCommands, ...pluginCommands]
        .where((cmd) => cmd.canExecuteFor(ref, file))
        .toList();

    if (allCommands.isEmpty) {
      _showSnackbar(context, 'No actions available for ${file.name}.');
      return;
    }

    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final selectedCommand = await showMenu<FileContextCommand>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40), // Position rect for the menu
        Offset.zero & overlay.size, // The container in which the menu is displayed
      ),
      items: allCommands.map((command) {
        return PopupMenuItem<FileContextCommand>(
          value: command,
          child: Row(
            children: [
              command.icon,
              const SizedBox(width: 8),
              Text(command.label),
            ],
          ),
        );
      }).toList(),
    );

    if (selectedCommand != null) {
      try {
        await selectedCommand.executeFor(ref, file);
        // After execution, refresh the directory if it's the current one
        ref.invalidate(directoryContentsProvider(file.isDirectory ? file.uri : Uri.parse(file.uri).resolve('.').toString()));
        sessionNotifier.updateProjectCounts(); // Update project counts

        if (selectedCommand is DeleteFileContextCommand || selectedCommand is CutFileContextCommand) {
          ref.invalidate(directoryContentsProvider(Uri.parse(file.uri).resolve('.').toString())); // Refresh parent dir
        }
        if (selectedCommand is CutFileContextCommand || selectedCommand is CopyFileContextCommand) {
          clipboardNotifier.state = ClipboardItem(uri: file.uri, isFolder: file.isDirectory, operation: selectedCommand is CutFileContextCommand ? ClipboardOperation.cut : ClipboardOperation.copy, name: file.name);
        } else if (selectedCommand is PasteFileContextCommand) {
           clipboardNotifier.state = null; // Clear clipboard after paste
        }
      } catch (e, st) {
        _showSnackbar(context, 'Action failed: $e');
        ref.read(logProvider.notifier).add('Context command error: $e\n$st');
      }
    }
  }

  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _showTextInputDialog(BuildContext context, {required String title, required String labelText, String? hintText, String? initialValue}) {
    TextEditingController controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: labelText, hintText: hintText),
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context, controller.text),
            ),
          ],
        );
      },
    );
  }
}

/// Displays a small badge for file extensions.
class _FileExtensionTag extends ConsumerWidget {
  final String fileName;
  const _FileExtensionTag({required this.fileName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ext = fileName.split('.').last.toUpperCase();
    if (ext.isEmpty || fileName == ext) return const SizedBox.shrink(); // No extension or just a dotfile

    // Example of a small badge style, can be customized
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        ext,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Generic File Explorer Context Commands (e.g., Rename, Delete, Cut, Copy, Paste)
/// These are distinct from app-wide Commands (like save) and plugin-specific commands.
abstract class FileExplorerContextCommands {
  // Implementations of these commands are below
}

class RenameFileContextCommand extends BaseFileContextCommand {
  RenameFileContextCommand() : super(
    id: 'rename_file',
    label: 'Rename',
    icon: const Icon(Icons.drive_file_rename_outline, size: 20),
    sourcePlugin: 'CoreExplorer',
    canExecuteFor: (ref, item) => true, // Always allow rename
    executeFor: (ref, item) async {
      final newName = await (ref.context
              .findAncestorStateOfType<ProjectExplorerViewState>()
              ?.widget as ProjectExplorerView)
          ._showTextInputDialog(ref.context, title: 'Rename ${item.name}', labelText: 'New Name', initialValue: item.name);
      if (newName != null && newName.isNotEmpty && newName != item.name) {
        await ref.read(fileHandlerProvider).renameDocumentFile(item, newName);
        _showSnackbar(ref.context, 'Renamed "${item.name}" to "$newName".');
      }
    },
  );
}

class DeleteFileContextCommand extends BaseFileContextCommand {
  DeleteFileContextCommand() : super(
    id: 'delete_file',
    label: 'Delete',
    icon: const Icon(Icons.delete_outline, size: 20),
    sourcePlugin: 'CoreExplorer',
    canExecuteFor: (ref, item) => true, // Always allow delete
    executeFor: (ref, item) async {
      final confirm = await showDialog<bool>(
        context: ref.context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${item.isDirectory ? 'Folder' : 'File'}'),
          content: Text('Are you sure you want to delete "${item.name}"? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
          ],
        ),
      ) ?? false;
      if (confirm) {
        await ref.read(fileHandlerProvider).deleteDocumentFile(item);
        _showSnackbar(ref.context, 'Deleted "${item.name}".');
      }
    },
  );
}

class CopyFileContextCommand extends BaseFileContextCommand {
  CopyFileContextCommand() : super(
    id: 'copy_file',
    label: 'Copy',
    icon: const Icon(Icons.content_copy, size: 20),
    sourcePlugin: 'CoreExplorer',
    canExecuteFor: (ref, item) => true, // Always allow copy
    executeFor: (ref, item) async {
      ref.read(clipboardProvider.notifier).state = ClipboardItem(uri: item.uri, isFolder: item.isDirectory, operation: ClipboardOperation.copy, name: item.name);
      _showSnackbar(ref.context, 'Copied "${item.name}" to clipboard.');
    },
  );
}

class CutFileContextCommand extends BaseFileContextCommand {
  CutFileContextCommand() : super(
    id: 'cut_file',
    label: 'Cut',
    icon: const Icon(Icons.content_cut, size: 20),
    sourcePlugin: 'CoreExplorer',
    canExecuteFor: (ref, item) => true, // Always allow cut
    executeFor: (ref, item) async {
      ref.read(clipboardProvider.notifier).state = ClipboardItem(uri: item.uri, isFolder: item.isDirectory, operation: ClipboardOperation.cut, name: item.name);
      _showSnackbar(ref.context, 'Cut "${item.name}" to clipboard.');
    },
  );
}

class PasteFileContextCommand extends BaseFileContextCommand {
  PasteFileContextCommand() : super(
    id: 'paste_file',
    label: 'Paste',
    icon: const Icon(Icons.content_paste, size: 20),
    sourcePlugin: 'CoreExplorer',
    canExecuteFor: (ref, item) {
      final clipboardItem = ref.watch(clipboardProvider);
      return item.isDirectory && clipboardItem != null; // Only paste into folders if clipboard has item
    },
    executeFor: (ref, item) async {
      final clipboardItem = ref.read(clipboardProvider);
      if (clipboardItem == null) {
        _showSnackbar(ref.context, 'Nothing to paste.');
        return;
      }
      final fileHandler = ref.read(fileHandlerProvider);
      final sessionNotifier = ref.read(sessionProvider.notifier);
      final isCut = clipboardItem.operation == ClipboardOperation.cut;
      final opText = isCut ? 'Moving' : 'Copying';

      try {
        if (isCut) {
          await fileHandler.moveDocumentFile(
            await fileHandler.getFileMetadata(clipboardItem.uri)!, // Get fresh metadata
            item.uri, // Paste into this folder
            newName: clipboardItem.name, // Keep original name
          );
        } else {
          await fileHandler.copyDocumentFile(
            await fileHandler.getFileMetadata(clipboardItem.uri)!,
            item.uri, // Paste into this folder
            newName: clipboardItem.name, // Keep original name
          );
        }
        ref.read(clipboardProvider.notifier).state = null; // Clear clipboard
        ref.invalidate(directoryContentsProvider(item.uri)); // Refresh destination folder
        sessionNotifier.updateProjectCounts(); // Update counts
        _showSnackbar(ref.context, '$opText "${clipboardItem.name}" completed.');
      } catch (e, st) {
        _showSnackbar(ref.context, 'Failed to $opText "${clipboardItem.name}": $e');
        ref.read(logProvider.notifier).add('Context paste error: $e\n$st');
      }
    },
  );
}

// Helper function for snackbars (can be moved to a shared utility if many widgets use it)
void _showSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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