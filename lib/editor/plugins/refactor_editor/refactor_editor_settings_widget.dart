// =========================================
// UPDATED: lib/editor/plugins/refactor_editor/refactor_editor_settings_widget.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../explorer/common/file_explorer_dialogs.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/toast.dart';
import 'refactor_editor_models.dart';

class RefactorEditorSettingsUI extends ConsumerWidget {
  final RefactorSettings settings;

  const RefactorEditorSettingsUI({super.key, required this.settings});

  void _updateSettings(WidgetRef ref, RefactorSettings newSettings) {
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }

  Future<void> _importFromGitignore(WidgetRef ref) {
    // ... (This method's logic remains the same, but now it operates on Sets)
    final repo = ref.read(projectRepositoryProvider);
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (repo == null || project == null) {
      MachineToast.error('A project must be open to import from .gitignore');
      return Future.value();
    }

    try {
      final gitignoreFile = await repo.fileHandler.resolvePath(project.rootUri, '.gitignore');
      if (gitignoreFile == null) {
        MachineToast.error('.gitignore file not found in the project root.');
        return Future.value();
      }

      final content = await repo.readFile(gitignoreFile.uri);
      final patterns = content
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toSet();

      final newIgnoredPatterns = {...settings.ignoredGlobPatterns, ...patterns};
      _updateSettings(ref, RefactorSettings(ignoredGlobPatterns: newIgnoredPatterns, supportedExtensions: settings.supportedExtensions));
      MachineToast.info('Imported ${patterns.length} new patterns from .gitignore');
    } catch (e) {
      MachineToast.error('Failed to read .gitignore: $e');
    }
    return Future.value();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Configuration', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        _buildEditableList(
          context,
          ref,
          title: 'Supported File Extensions',
          items: settings.supportedExtensions,
          onChanged: (newItems) {
            _updateSettings(ref, RefactorSettings(supportedExtensions: newItems, ignoredGlobPatterns: settings.ignoredGlobPatterns));
          },
        ),
        const SizedBox(height: 24),
        _buildEditableList(
          context,
          ref,
          title: 'Ignored Glob Patterns', // <-- RENAMED
          items: settings.ignoredGlobPatterns,
          onChanged: (newItems) {
            _updateSettings(ref, RefactorSettings(ignoredGlobPatterns: newItems, supportedExtensions: settings.supportedExtensions));
          },
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('Import from .gitignore'),
            onPressed: () => _importFromGitignore(ref),
          ),
        ),
      ],
    );
  }

  Widget _buildEditableList(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required Set<String> items, // <-- CHANGED TO SET
    required ValueChanged<Set<String>> onChanged, // <-- CHANGED TO SET
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            // SEPARATE CLEAR BUTTON
            if (items.isNotEmpty)
              IconButton(
                icon: Icon(Icons.clear_all, color: Colors.red.shade300),
                tooltip: 'Clear all patterns',
                onPressed: () => onChanged({}),
              ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add new pattern',
              onPressed: () async {
                final newItem = await showTextInputDialog(context, title: 'Add New Pattern');
                if (newItem != null && newItem.trim().isNotEmpty) {
                  onChanged({...items, newItem.trim()});
                }
              },
            )
          ],
        ),
        const Divider(),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('No patterns configured.', style: TextStyle(fontStyle: FontStyle.italic)),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: items.map((item) {
            return Chip(
              label: Text(item),
              onDeleted: () {
                final newItems = Set<String>.from(items)..remove(item);
                onChanged(newItems);
              },
            );
          }).toList(),
        ),
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