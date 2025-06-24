// lib/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/plugins/plugin_registry.dart';
import '../command/command_notifier.dart';
import 'settings_notifier.dart';
import 'settings_models.dart';

// NEW: A map of available accent colors for the UI.
const Map<String, Color> kAccentColors = {
  'Orange':
      Colors.orange, // TODO: find the old accent color and add a color picker
  'Red': Colors.red,
  'Blue': Colors.blue,
  'Green': Colors.green,
  'Purple': Colors.purple,
  'Teal': Colors.teal,
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _buildPluginSettingsList(context, ref),
    );
  }

  Widget _buildPluginSettingsList(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final settings = ref.watch(settingsProvider);
    // REFACTOR: This cast is now correct because we know it's a GeneralSettings object.
    final generalSettings =
        settings.pluginSettings[GeneralSettings] as GeneralSettings?;

    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('Command Customization'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pushNamed(context, '/command-settings'),
        ),
        if (generalSettings != null)
          _GeneralSettingsCard(settings: generalSettings),
        ...plugins
            .where((p) => p.settings != null)
            .map(
              (plugin) => _PluginSettingsCard(
                plugin: plugin,
                // REFACTOR: This cast is also correct.
                settings:
                    settings.pluginSettings[plugin.settings.runtimeType]!
                        as PluginSettings,
              ),
            ),
      ],
    );
  }
}

// ... (_GeneralSettingsCard is unchanged)
class _GeneralSettingsCard extends ConsumerWidget {
  final GeneralSettings settings;
  const _GeneralSettingsCard({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(settingsProvider.notifier);

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // REFACTOR: Separate Theme and Fullscreen sections for clarity.
            _buildThemeSettings(context, notifier),
            const Divider(height: 32),
            _buildFullscreenSettings(context, notifier),
          ],
        ),
      ),
    );
  }

  // NEW: Widget for Theme settings
  Widget _buildThemeSettings(BuildContext context, SettingsNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: Theme.of(context).textTheme.titleLarge),
        /*
        const SizedBox(height: 16),
        DropdownButtonFormField<ThemeMode>(
          decoration: const InputDecoration(
            labelText: 'Theme Mode',
            border: OutlineInputBorder(),
          ),
          value: settings.themeMode,
          items: const [
            DropdownMenuItem(value: ThemeMode.system, child: Text('System Default')),
            DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
            DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
          ],
          onChanged: (value) {
            if (value != null) {
              notifier.updatePluginSettings(settings.copyWith(themeMode: value));
            }
          },
        ),*/
        const SizedBox(height: 20),
        Text('Accent Color', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              kAccentColors.entries.map((entry) {
                final color = entry.value;
                final isSelected = settings.accentColorValue == color.value;
                return GestureDetector(
                  onTap: () {
                    notifier.updatePluginSettings(
                      settings.copyWith(accentColorValue: color.value),
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border:
                          isSelected
                              ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 3,
                              )
                              : null,
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  // NEW: Widget for Fullscreen settings
  Widget _buildFullscreenSettings(
    BuildContext context,
    SettingsNotifier notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fullscreen Mode', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Hide App Bar'),
          value: settings.hideAppBarInFullScreen,
          onChanged: (value) {
            notifier.updatePluginSettings(
              settings.copyWith(hideAppBarInFullScreen: value),
            );
          },
        ),
        SwitchListTile(
          title: const Text('Hide Tab Bar'),
          value: settings.hideTabBarInFullScreen,
          onChanged: (value) {
            notifier.updatePluginSettings(
              settings.copyWith(hideTabBarInFullScreen: value),
            );
          },
        ),
        SwitchListTile(
          title: const Text('Hide Bottom Toolbar'),
          value: settings.hideBottomToolbarInFullScreen,
          onChanged: (value) {
            notifier.updatePluginSettings(
              settings.copyWith(hideBottomToolbarInFullScreen: value),
            );
          },
        ),
      ],
    );
  }
}

class _PluginSettingsCard extends ConsumerWidget {
  final EditorPlugin plugin;
  final PluginSettings settings;

  const _PluginSettingsCard({required this.plugin, required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                plugin.icon,
                const SizedBox(width: 12),
                Text(
                  plugin.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            plugin.buildSettingsUI(settings),
          ],
        ),
      ),
    );
  }
}

class CommandSettingsScreen extends ConsumerWidget {
  const CommandSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commandProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Command Customization')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Group'),
        onPressed:
            () => showDialog(
              context: context,
              builder: (_) => GroupEditorDialog(ref: ref),
            ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          _buildSection(context, ref, 'App Bar', 'appBar', state.appBarOrder),
          _buildSection(
            context,
            ref,
            'Plugin Toolbar',
            'pluginToolbar',
            state.pluginToolbarOrder,
          ),
          ...state.commandGroups.values.map(
            (group) => _buildGroupSection(context, ref, group),
          ),
          _buildSection(
            context,
            ref,
            'Hidden Commands',
            'hidden',
            state.hiddenOrder,
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSection(
    BuildContext context,
    WidgetRef ref,
    CommandGroup group,
  ) {
    return ExpansionTile(
      leading: group.icon,
      title: Text(group.label),
      initiallyExpanded: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed:
                () => showDialog(
                  context: context,
                  builder: (_) => GroupEditorDialog(ref: ref, group: group),
                ),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed:
                () => ref.read(commandProvider.notifier).deleteGroup(group.id),
          ),
        ],
      ),
      children: [
        _buildReorderableList(context, ref, group.commandIds, listId: group.id),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    WidgetRef ref,
    String title,
    String listId,
    List<String> itemIds,
  ) {
    return ExpansionTile(
      title: Text(title),
      initiallyExpanded: true,
      children: [_buildReorderableList(context, ref, itemIds, listId: listId)],
    );
  }

  Widget _buildReorderableList(
    BuildContext context,
    WidgetRef ref,
    List<String> itemIds, {
    required String listId,
  }) {
    final state = ref.watch(commandProvider);
    final notifier = ref.read(commandProvider.notifier);

    return Column(
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemIds.length,
          itemBuilder: (ctx, index) {
            final itemId = itemIds[index];
            final Widget itemWidget;

            if (state.commandGroups.containsKey(itemId)) {
              final group = state.commandGroups[itemId]!;
              itemWidget = ListTile(
                key: ValueKey(group.id),
                leading: const Icon(Icons.drag_handle),
                title: Row(
                  children: [
                    group.icon,
                    const SizedBox(width: 12),
                    Text(
                      group.label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                trailing:
                    listId == 'hidden'
                        ? null
                        : IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Remove from this list',
                          onPressed:
                              () => notifier.removeItemFromList(
                                itemId: itemId,
                                fromListId: listId,
                              ),
                        ),
              );
            } else {
              final sources = state.commandSources[itemId];
              if (sources == null || sources.isEmpty) {
                // This case should no longer happen due to sanitization, but it's good defensive coding.
                return ListTile(
                  key: ValueKey(itemId),
                  title: Text('Error: Stale command ID "$itemId"'),
                );
              }
              final command = notifier.getCommand(itemId, sources.first);
              if (command == null) {
                return ListTile(
                  key: ValueKey(itemId),
                  title: Text('Error: Command "$itemId" not found'),
                );
              }
              itemWidget = ListTile(
                key: ValueKey(
                  command.id + listId,
                ), // Key needs to be unique per list instance
                leading: const Icon(Icons.drag_handle),
                title: Row(
                  children: [
                    command.icon,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        command.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle:
                    sources.length > 1
                        ? Text('From: ${sources.join(', ')}')
                        : null,
                trailing:
                    listId == 'hidden'
                        ? null
                        : IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Remove from this list',
                          onPressed:
                              () => notifier.removeItemFromList(
                                itemId: command.id,
                                fromListId: listId,
                              ),
                        ),
              );
            }
            return itemWidget;
          },
          onReorder: (oldIndex, newIndex) {
            notifier.reorderItemInList(
              listId: listId,
              oldIndex: oldIndex,
              newIndex: newIndex,
            );
          },
        ),
        if (listId != 'hidden')
          Padding(
            padding: const EdgeInsets.only(right: 16.0, bottom: 8.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add item to this section',
                onPressed:
                    () => showDialog(
                      context: context,
                      builder: (_) => AddItemDialog(ref: ref, toListId: listId),
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

// --- Dialogs ---

class AddItemDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final String toListId;
  const AddItemDialog({super.key, required this.ref, required this.toListId});

  @override
  ConsumerState<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends ConsumerState<AddItemDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () => setState(() => _query = _searchController.text.toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.ref.read(commandProvider.notifier);
    final state = widget.ref.watch(commandProvider);

    // CORRECTED: The dialog is now aware of its destination context.
    final bool isAddingToGroup = widget.toListId.startsWith('group_');

    // Get all available items to add.
    final allCommands =
        {
          for (var cmd in notifier.allRegisteredCommands) cmd.id: cmd,
        }.values.toList();
    final allGroups = state.commandGroups.values.toList();

    final query = _query;
    final filteredCommands =
        allCommands
            .where((cmd) => cmd.label.toLowerCase().contains(query))
            .toList();
    final filteredGroups =
        allGroups
            .where((group) => group.label.toLowerCase().contains(query))
            .toList();

    return AlertDialog(
      title: const Text('Add Item'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(labelText: 'Search items...'),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // CORRECTED: Conditionally show groups.
                  if (!isAddingToGroup && filteredGroups.isNotEmpty) ...[
                    const Text(
                      'Groups',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...filteredGroups.map(
                      (group) => ListTile(
                        leading: group.icon,
                        title: Text(group.label),
                        onTap: () {
                          notifier.addItemToList(
                            itemId: group.id,
                            toListId: widget.toListId,
                          );
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                    const Divider(),
                  ],
                  const Text(
                    'Commands',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...filteredCommands.map(
                    (command) => ListTile(
                      leading: command.icon,
                      title: Text(command.label),
                      subtitle: Text(command.sourcePlugin),
                      onTap: () {
                        notifier.addItemToList(
                          itemId: command.id,
                          toListId: widget.toListId,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GroupEditorDialog extends StatefulWidget {
  final WidgetRef ref;
  final CommandGroup? group;
  const GroupEditorDialog({super.key, required this.ref, this.group});

  @override
  State<GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<GroupEditorDialog> {
  late final TextEditingController _nameController;
  late String _selectedIconName;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group?.label ?? '');
    _selectedIconName =
        widget.group?.iconName ?? CommandIcon.availableIcons.keys.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final notifier = widget.ref.read(commandProvider.notifier);
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (widget.group == null) {
      notifier.createGroup(name: name, iconName: _selectedIconName);
    } else {
      notifier.updateGroup(
        widget.group!.id,
        newName: name,
        newIconName: _selectedIconName,
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.group == null ? 'New Command Group' : 'Edit Group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Group Name'),
            autofocus: true,
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CommandIcon.getIcon(_selectedIconName),
            title: const Text('Group Icon'),
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: () async {
              final String? newIcon = await showDialog(
                context: context,
                builder: (_) => const IconPickerDialog(),
              );
              if (newIcon != null) {
                setState(() => _selectedIconName = newIcon);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _onConfirm, child: const Text('Confirm')),
      ],
    );
  }
}

class IconPickerDialog extends StatelessWidget {
  const IconPickerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select an Icon'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
          ),
          itemCount: CommandIcon.availableIcons.length,
          itemBuilder: (context, index) {
            final iconName = CommandIcon.availableIcons.keys.elementAt(index);
            return IconButton(
              icon: CommandIcon.getIcon(iconName),
              onPressed: () => Navigator.of(context).pop(iconName),
              tooltip: iconName,
            );
          },
        ),
      ),
    );
  }
}
