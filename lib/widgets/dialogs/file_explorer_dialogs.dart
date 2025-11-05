// lib/explorer/common/file_explorer_dialogs.dart

import 'package:flutter/material.dart';

import '../../editor/plugins/editor_plugin_models.dart';

import '../../editor/tab_metadata_notifier.dart'; // <-- ADD THIS IMPORT

//TODO: check dependency

Future<EditorPlugin?> showOpenWithDialog(
  BuildContext context,
  List<EditorPlugin> plugins,
) async {
  return await showDialog<EditorPlugin>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: const Text('Open with...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children:
                plugins
                    .map(
                      (p) => ListTile(
                        leading: p.icon,
                        title: Text(p.name),
                        onTap: () => Navigator.of(ctx).pop(p),
                      ),
                    )
                    .toList(),
          ),
        ),
  );
}

Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
}) {
  TextEditingController controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('OK'),
            ),
          ],
        ),
  );
}

Future<bool> showConfirmDialog(
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

Future<bool> showCreateFileConfirmationDialog(
  BuildContext context, {
  required String relativePath,
}) async {
  return await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('File Not Found'),
              content: Text(
                'The file "$relativePath" does not exist.\n\nWould you like to create it, along with any missing parent directories?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Create'),
                ),
              ],
            ),
      ) ??
      false;
}

// NEW: An enum to represent the user's choice in the conflict dialog.
enum CacheConflictResolution {
  /// The user wants to apply their unsaved changes.
  loadCache,

  /// The user wants to discard their unsaved changes and load the latest from disk.
  loadDisk,
}

// NEW: A dialog specifically for handling cache conflicts.
Future<CacheConflictResolution?> showCacheConflictDialog(
  BuildContext context, {
  required String fileName,
}) async {
  return await showDialog<CacheConflictResolution>(
    context: context,
    barrierDismissible: false, // User must make a choice.
    builder:
        (ctx) => AlertDialog(
          title: const Text('Unsaved Changes Conflict'),
          content: Text(
            'The file "$fileName" has been modified by another application since you last opened it.\n\n'
            'Would you like to load your unsaved changes, or discard them and reload the file from disk?',
          ),
          actions: [
            TextButton(
              onPressed:
                  () => Navigator.pop(ctx, CacheConflictResolution.loadDisk),
              child: const Text('Discard & Reload'),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.pop(ctx, CacheConflictResolution.loadCache),
              child: const Text('Load Unsaved Changes'),
            ),
          ],
        ),
  );
}

// NEW: An enum to represent the user's choice in the unsaved changes dialog.
enum UnsavedChangesAction { save, discard, cancel }

// NEW: A dialog for handling unsaved changes.
Future<UnsavedChangesAction?> showUnsavedChangesDialog(
  BuildContext context, {
  required List<TabMetadata> dirtyFiles,
}) async {
  final fileNames = dirtyFiles.map((e) => e.file.name).join('\n');

  return await showDialog<UnsavedChangesAction>(
    context: context,
    barrierDismissible: false, // User must make an explicit choice.
    builder:
        (ctx) => AlertDialog(
          title: const Text('Unsaved Changes'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Do you want to save the changes you made to the following ${dirtyFiles.length} file(s)?',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(child: Text(fileNames)),
                ),
                const SizedBox(height: 8),
                const Text("Your changes will be lost if you don't save them."),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed:
                  () => Navigator.of(ctx).pop(UnsavedChangesAction.cancel),
            ),
            TextButton(
              child: const Text('Discard'),
              onPressed:
                  () => Navigator.of(ctx).pop(UnsavedChangesAction.discard),
            ),
            FilledButton(
              child: const Text('Save All'),
              onPressed: () => Navigator.of(ctx).pop(UnsavedChangesAction.save),
            ),
          ],
        ),
  );
}
