import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../command/command_models.dart';
import '../termux_terminal_models.dart';

class TermuxSettingsWidget extends ConsumerStatefulWidget {
  final TermuxTerminalSettings settings;
  final void Function(TermuxTerminalSettings) onChanged;

  const TermuxSettingsWidget({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  ConsumerState<TermuxSettingsWidget> createState() =>
      _TermuxSettingsWidgetState();
}

class _TermuxSettingsWidgetState extends ConsumerState<TermuxSettingsWidget> {
  // Local subset of icons useful for terminal actions
  static const Map<String, IconData> _pickerIcons = {
    'terminal': Icons.terminal,
    'play': Icons.play_arrow,
    'stop': Icons.stop,
    'refresh': Icons.refresh,
    'git': Icons.commit,
    'folder': Icons.folder_open,
    'list': Icons.list,
    'build': Icons.build,
    'debug': Icons.bug_report,
    'upload': Icons.upload,
    'download': Icons.download,
    'delete': Icons.delete_outline,
    'save': Icons.save_outlined,
    'code': Icons.code,
    'settings': Icons.settings_outlined,
    'star': Icons.star_border,
    'flash': Icons.flash_on,
    'link': Icons.link,
  };

  void _addShortcut() {
    _showShortcutDialog();
  }

  void _editShortcut(int index) {
    _showShortcutDialog(
      existingShortcut: widget.settings.customShortcuts[index],
      index: index,
    );
  }

  void _removeShortcut(int index) {
    final newList =
        List<TerminalShortcut>.from(widget.settings.customShortcuts);
    newList.removeAt(index);
    widget.onChanged(widget.settings.copyWith(customShortcuts: newList));
  }

  void _reorderShortcuts(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final newList =
        List<TerminalShortcut>.from(widget.settings.customShortcuts);
    final item = newList.removeAt(oldIndex);
    newList.insert(newIndex, item);
    widget.onChanged(widget.settings.copyWith(customShortcuts: newList));
  }

  Future<void> _showShortcutDialog(
      {TerminalShortcut? existingShortcut, int? index}) async {
    final result = await showDialog<TerminalShortcut>(
      context: context,
      builder: (context) => _ShortcutDialog(
        initialValue: existingShortcut,
        availableIcons: _pickerIcons,
      ),
    );

    if (result != null) {
      final newList =
          List<TerminalShortcut>.from(widget.settings.customShortcuts);
      if (index != null) {
        newList[index] = result;
      } else {
        newList.add(result);
      }
      widget.onChanged(widget.settings.copyWith(customShortcuts: newList));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- General Settings Section ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                initialValue: widget.settings.fontSize.toString(),
                decoration: const InputDecoration(
                  labelText: 'Font Size',
                  helperText: 'Recommended: 12.0 to 16.0',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  final size = double.tryParse(val);
                  if (size != null && size > 0) {
                    widget.onChanged(
                        widget.settings.copyWith(fontSize: size));
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: widget.settings.termuxWorkDir,
                decoration: const InputDecoration(
                  labelText: 'Default Working Directory',
                  helperText: 'The directory where new terminals will start.',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (val) => widget.onChanged(
                    widget.settings.copyWith(termuxWorkDir: val.trim())),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: widget.settings.shellCommand,
                decoration: const InputDecoration(
                  labelText: 'Shell Executable',
                  helperText: 'e.g., bash, zsh, fish',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (val) => widget.onChanged(
                    widget.settings.copyWith(shellCommand: val.trim())),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Dark Theme'),
                value: widget.settings.useDarkTheme,
                onChanged: (val) => widget.onChanged(
                    widget.settings.copyWith(useDarkTheme: val)),
              ),
            ],
          ),
        ),

        const Divider(),

        // --- Custom Shortcuts Section ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Custom Shortcuts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add Shortcut',
                onPressed: _addShortcut,
              ),
            ],
          ),
        ),

        if (widget.settings.customShortcuts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'No shortcuts added. Add one to quickly run commands.',
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.settings.customShortcuts.length,
            onReorder: _reorderShortcuts,
            itemBuilder: (context, index) {
              final shortcut = widget.settings.customShortcuts[index];
              final iconData =
                  _pickerIcons[shortcut.iconName] ?? Icons.code;

              return ListTile(
                key: ValueKey(shortcut.hashCode), // Simple key for reordering
                leading: Icon(iconData),
                title: Text(shortcut.label),
                subtitle: Text(
                  shortcut.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editShortcut(index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      onPressed: () => _removeShortcut(index),
                    ),
                    const SizedBox(width: 8), // Spacing for drag handle
                    const Icon(Icons.drag_handle, color: Colors.grey),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ShortcutDialog extends StatefulWidget {
  final TerminalShortcut? initialValue;
  final Map<String, IconData> availableIcons;

  const _ShortcutDialog({
    this.initialValue,
    required this.availableIcons,
  });

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  late TextEditingController _labelController;
  late TextEditingController _commandController;
  late String _selectedIconName;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.initialValue?.label ?? '');
    _commandController =
        TextEditingController(text: widget.initialValue?.command ?? '');
    _selectedIconName = widget.initialValue?.iconName ?? 'code';
  }

  @override
  void dispose() {
    _labelController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  void _save() {
    if (_labelController.text.isEmpty || _commandController.text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(TerminalShortcut(
      label: _labelController.text,
      command: _commandController.text,
      iconName: _selectedIconName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialValue == null ? 'Add Shortcut' : 'Edit Shortcut'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g., Git Status',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commandController,
              decoration: const InputDecoration(
                labelText: 'Command',
                hintText: 'e.g., git status',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Select Icon'),
            ),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withAlpha(50)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: widget.availableIcons.length,
                itemBuilder: (context, index) {
                  final key = widget.availableIcons.keys.elementAt(index);
                  final icon = widget.availableIcons[key]!;
                  final isSelected = key == _selectedIconName;

                  return InkWell(
                    onTap: () => setState(() => _selectedIconName = key),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary.withAlpha(50)
                            : null,
                        border: isSelected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}