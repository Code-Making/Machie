import 'package:flutter/material.dart';

import '../../../widgets/dialogs/file_explorer_dialogs.dart';
import 'search_explorer_settings.dart';

class SearchExplorerSettingsUI extends StatelessWidget {
  final SearchExplorerSettings settings;
  final void Function(SearchExplorerSettings) onChanged;

  const SearchExplorerSettingsUI({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search Configuration',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        _buildEditableList(
          context,
          title: 'Search Only in these File Extensions',
          subtitle: 'Leave empty to search all files that are not ignored.',
          items: settings.supportedExtensions,
          onListChanged: (newItems) {
            onChanged(settings.copyWith(supportedExtensions: newItems));
          },
        ),
        const SizedBox(height: 24),
        _buildEditableList(
          context,
          title: 'Global Ignored Glob Patterns',
          items: settings.ignoredGlobPatterns,
          onListChanged: (newItems) {
            onChanged(settings.copyWith(ignoredGlobPatterns: newItems));
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
            onChanged(settings.copyWith(useProjectGitignore: newValue));
          },
        ),
      ],
    );
  }

  Widget _buildEditableList(
    BuildContext context, {
    required String title,
    String? subtitle,
    required Set<String> items,
    required ValueChanged<Set<String>> onListChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
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
          children:
              items.map((item) {
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
