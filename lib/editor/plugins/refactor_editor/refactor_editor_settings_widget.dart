import 'package:flutter/material.dart';

import '../../../widgets/dialogs/file_explorer_dialogs.dart';
import 'refactor_editor_models.dart';

class RefactorEditorSettingsUI extends StatelessWidget {
  final RefactorSettings settings;
  final void Function(RefactorSettings) onChanged;

  const RefactorEditorSettingsUI({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Configuration', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        _buildEditableList(
          context,
          title: 'Supported File Extensions',
          items: settings.supportedExtensions,
          onListChanged: (newItems) {
            onChanged(
              settings.copyWith(supportedExtensions: newItems),
            );
          },
        ),
        const SizedBox(height: 24),
        _buildEditableList(
          context,
          title: 'Global Ignored Glob Patterns',
          items: settings.ignoredGlobPatterns,
          onListChanged: (newItems) {
            onChanged(
              settings.copyWith(ignoredGlobPatterns: newItems),
            );
          },
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Use Project .gitignore'),
          subtitle: const Text(
            'Automatically use patterns from the .gitignore file in the current project root, if it exists.',
          ),
          value: settings.useProjectGitignore,
          onChanged: (newValue) {
            onChanged(
              settings.copyWith(useProjectGitignore: newValue),
            );
          },
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Mark moved files as dirty instead of auto-saving'),
          subtitle: const Text(
            'When a file is moved, if this is on, its updated internal paths will be applied as unsaved changes. If off, the file will be saved directly to disk.',
          ),
          value: settings.updateInternalPathsAsDirty,
          onChanged: (newValue) {
            onChanged(
              settings.copyWith(updateInternalPathsAsDirty: newValue),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEditableList(
    BuildContext context, {
    required String title,
    required Set<String> items,
    required ValueChanged<Set<String>> onListChanged,
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
                onPressed: () => onListChanged({}),
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
                  onListChanged({...items, newItem.trim()});
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
          children: items.map((item) {
            return Chip(
              label: Text(item),
              onDeleted: () {
                final newItems = Set<String>.from(items)..remove(item);
                onListChanged(newItems);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}