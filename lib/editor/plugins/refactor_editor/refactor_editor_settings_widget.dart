// =========================================
// NEW FILE: lib/editor/plugins/refactor_editor/refactor_editor_settings_widget.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/toast.dart';
import 'folder_picker_dialog.dart';
import 'refactor_editor_models.dart';
import '../../../data/file_handler/file_handler.dart';

class RefactorEditorSettingsUI extends ConsumerWidget {
  final RefactorSettings settings;
  const RefactorEditorSettingsUI({super.key, required this.settings});

  void _updateSettings(WidgetRef ref, RefactorSettings newSettings) {
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }

  Future<void> _importFromGitignore(BuildContext context, WidgetRef ref) async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    final repo = ref.read(projectRepositoryProvider);
    if (project == null || repo == null) {
      MachineToast.error('A project must be open to import from .gitignore');
      return;
    }

    final gitignoreFile = await repo.fileHandler.resolvePath(project.rootUri, '.gitignore');
    if (gitignoreFile == null) {
      MachineToast.error('.gitignore file not found in the project root.');
      return;
    }

    try {
      final content = await repo.readFile(gitignoreFile.uri);
      final lines = content
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .map((line) => line.endsWith('/') ? line.substring(0, line.length - 1) : line)
          .toList();

      final newIgnoredFolders = {...settings.ignoredFolders, ...lines}.toList();
      _updateSettings(ref, RefactorSettings(ignoredFolders: newIgnoredFolders, supportedExtensions: settings.supportedExtensions));
      MachineToast.info('Imported ${lines.length} patterns from .gitignore');
    } catch (e) {
      MachineToast.error('Failed to read .gitignore: $e');
    }
  }

  Future<void> _addIgnoredFolder(BuildContext context, WidgetRef ref) async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null) {
      MachineToast.error('A project must be open to select a folder.');
      return;
    }

    final selectedPath = await showDialog<String>(
      context: context,
      builder: (_) => const FolderPickerDialog(),
    );

    if (selectedPath != null) {
      final newIgnoredFolders = {...settings.ignoredFolders, selectedPath}.toList();
      _updateSettings(ref, RefactorSettings(ignoredFolders: newIgnoredFolders, supportedExtensions: settings.supportedExtensions));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEditableList(
          ref: ref,
          title: 'Supported File Extensions',
          items: settings.supportedExtensions,
          onUpdate: (newItems) => _updateSettings(ref, RefactorSettings(supportedExtensions: newItems, ignoredFolders: settings.ignoredFolders)),
        ),
        const SizedBox(height: 24),
        _buildEditableList(
          ref: ref,
          title: 'Ignored Folders & Patterns',
          items: settings.ignoredFolders,
          onUpdate: (newItems) => _updateSettings(ref, RefactorSettings(ignoredFolders: newItems, supportedExtensions: settings.supportedExtensions)),
          extraActions: [
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Folder'),
              onPressed: () => _addIgnoredFolder(context, ref),
            ),
            TextButton.icon(
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import from .gitignore'),
              onPressed: () => _importFromGitignore(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditableList({
    required WidgetRef ref,
    required String title,
    required List<String> items,
    required ValueChanged<List<String>> onUpdate,
    List<Widget>? extraActions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: Theme.of(ref.context).textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () async {
                final newItem = await showDialog<String>(
                  context: ref.context,
                  builder: (_) => _TextInputDialog(title: 'Add New Entry'),
                );
                if (newItem != null && newItem.isNotEmpty) {
                  onUpdate([...items, newItem]);
                }
              },
            ),
          ],
        ),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: items.map((item) {
            return Chip(
              label: Text(item),
              onDeleted: () {
                final newItems = List<String>.from(items)..remove(item);
                onUpdate(newItems);
              },
            );
          }).toList(),
        ),
        if (extraActions != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            children: extraActions,
          ),
        ]
      ],
    );
  }
}

class _TextInputDialog extends StatefulWidget {
  final String title;
  const _TextInputDialog({required this.title});

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(controller: _controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: const Text('Add')),
      ],
    );
  }
}