// =========================================
// UPDATED: lib/editor/plugins/refactor_editor/refactor_editor_settings_widget.dart
// =========================================

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../explorer/common/file_explorer_dialogs.dart';
import '../../../settings/settings_notifier.dart';
import 'refactor_editor_models.dart';

// No longer need these imports for this UI widget
// import '../../../app/app_notifier.dart';
// import '../../../data/repositories/project_repository.dart';
// import '../../../utils/toast.dart';

class RefactorEditorSettingsUI extends ConsumerWidget {
  final RefactorSettings settings;

  const RefactorEditorSettingsUI({super.key, required this.settings});

  void _updateSettings(WidgetRef ref, RefactorSettings newSettings) {
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }

  // REMOVED: _importFromGitignore method is no longer needed in the UI.

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
            _updateSettings(
              ref,
              RefactorSettings(
                supportedExtensions: newItems,
                ignoredGlobPatterns: settings.ignoredGlobPatterns,
                useProjectGitignore: settings.useProjectGitignore,
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        _buildEditableList(
          context,
          ref,
          title: 'Global Ignored Glob Patterns', // Clarify this is global
          items: settings.ignoredGlobPatterns,
          onChanged: (newItems) {
            _updateSettings(
              ref,
              RefactorSettings(
                ignoredGlobPatterns: newItems,
                supportedExtensions: settings.supportedExtensions,
                useProjectGitignore: settings.useProjectGitignore,
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // --- REPLACED BUTTON WITH SWITCH ---
        SwitchListTile(
          title: const Text('Use Project .gitignore'),
          subtitle: const Text(
            'Automatically use patterns from the .gitignore file in the current project root, if it exists.',
          ),
          value: settings.useProjectGitignore,
          onChanged: (newValue) {
            _updateSettings(
              ref,
              RefactorSettings(
                useProjectGitignore: newValue,
                supportedExtensions: settings.supportedExtensions,
                ignoredGlobPatterns: settings.ignoredGlobPatterns,
              ),
            );
          },
        ),
        // --- END REPLACEMENT ---
      ],
    );
  }

  // ... (_buildEditableList method remains unchanged)
  Widget _buildEditableList(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required Set<String> items,
    required ValueChanged<Set<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
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
                final newItem = await showTextInputDialog(
                  context,
                  title: 'Add New Pattern',
                );
                if (newItem != null && newItem.trim().isNotEmpty) {
                  onChanged({...items, newItem.trim()});
                }
              },
            ),
          ],
        ),
        const Divider(),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'No patterns configured.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children:
              items.map((item) {
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
