// =========================================
// UPDATED: lib/settings/settings_screen.dart
// =========================================

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_notifier.dart';
import '../command/command_notifier.dart';
import '../editor/plugins/editor_plugin_registry.dart';
import 'settings_notifier.dart';

const Map<String, Color> kAccentColors = {
  'Orange': Colors.orange,
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
    final allPlugins = ref.watch(activePluginsProvider);
    final settings = ref.watch(settingsProvider);
    final generalSettings =
        settings.pluginSettings[GeneralSettings] as GeneralSettings?;
        
    // --- NEW SORTING LOGIC ---
    // 1. Get the currently active plugin, if any.
    final activePlugin = ref.watch(appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab?.plugin,
    ));

    // 2. Create a mutable copy of the plugins that have settings.
    final pluginsWithSettings = allPlugins.where((p) => p.settings != null).toList();

    // 3. If there's an active plugin with settings, move it to the top.
    if (activePlugin != null && pluginsWithSettings.contains(activePlugin)) {
      pluginsWithSettings.remove(activePlugin);
      pluginsWithSettings.insert(0, activePlugin);
    }
    // --- END NEW SORTING LOGIC ---

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
        // 4. Use the newly sorted list to build the cards.
        ...pluginsWithSettings
            .map(
              (plugin) => _PluginSettingsCard(
                plugin: plugin,
                settings:
                    settings.pluginSettings[plugin.settings.runtimeType]!
                        as PluginSettings,
              ),
            ),
      ],
    );
  }
}

// ... (_GeneralSettingsCard and _PluginSettingsCard are unchanged) ...
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
            _buildThemeSettings(context, notifier),
            const Divider(height: 32),
            _buildFileExplorerSettings(
              context,
              notifier,
            ), // <-- ADDED THIS SECTION
            const Divider(height: 32),
            _buildFullscreenSettings(context, notifier),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSettings(BuildContext context, SettingsNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: Theme.of(context).textTheme.titleLarge),
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

  Widget _buildFileExplorerSettings(
    BuildContext context,
    SettingsNotifier notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('File Explorer', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Show Hidden Files'),
          subtitle: const Text(
            'Displays files and folders starting with a dot (e.g., .git)',
          ),
          value: settings.showHiddenFiles,
          onChanged: (value) {
            notifier.updatePluginSettings(
              settings.copyWith(showHiddenFiles: value),
            );
          },
        ),
      ],
    );
  }

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

// REFACTORED: This screen is now fully dynamic.
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
          // Dynamically build a section for each available position
          ...state.availablePositions.map((position) {
            return _buildSection(
              context,
              ref,
              position,
              state.orderedCommandsByPosition[position.id] ?? [],
            );
          }),
          ...state.commandGroups.values.map(
            (group) => _buildGroupSection(context, ref, group),
          ),
          // Hidden commands section
          _buildSection(
            context,
            ref,
            AppCommandPositions.hidden,
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
    // ... (This widget is mostly unchanged, but its reorderable list now uses positionId) ...
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
        _buildReorderableList(
          context,
          ref,
          group.commandIds,
          positionId: group.id,
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    WidgetRef ref,
    CommandPosition position,
    List<String> itemIds,
  ) {
    return ExpansionTile(
      leading: Icon(position.icon),
      title: Text(position.label),
      initiallyExpanded: true,
      children: [
        _buildReorderableList(context, ref, itemIds, positionId: position.id),
      ],
    );
  }

  Widget _buildReorderableList(
    BuildContext context,
    WidgetRef ref,
    List<String> itemIds, {
    required String positionId,
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
                    positionId == AppCommandPositions.hidden.id
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
                                fromPositionId: positionId,
                              ),
                        ),
              );
            } else {
              final sources = state.commandSources[itemId];
              if (sources == null || sources.isEmpty) {
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
                key: ValueKey(command.id + positionId),
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
                    positionId == AppCommandPositions.hidden.id
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
                                fromPositionId: positionId,
                              ),
                        ),
              );
            }
            return itemWidget;
          },
          onReorder: (oldIndex, newIndex) {
            notifier.reorderItemInList(
              positionId: positionId,
              oldIndex: oldIndex,
              newIndex: newIndex,
            );
          },
        ),
        if (positionId != AppCommandPositions.hidden.id)
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
                      builder:
                          (_) =>
                              AddItemDialog(ref: ref, toPositionId: positionId),
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

// REFACTORED: The AddItemDialog now uses positionId.
class AddItemDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final String toPositionId;
  const AddItemDialog({
    super.key,
    required this.ref,
    required this.toPositionId,
  });

  @override
  ConsumerState<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends ConsumerState<AddItemDialog> {
  // ... (unchanged)
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
    final bool isAddingToGroup = widget.toPositionId.startsWith('group_');
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
                            toPositionId: widget.toPositionId,
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
                          toPositionId: widget.toPositionId,
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

// ... (GroupEditorDialog and IconPickerDialog are unchanged) ...
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
  late bool _showLabels; // <-- ADDED

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group?.label ?? '');
    _selectedIconName =
        widget.group?.iconName ?? CommandIcon.availableIcons.keys.first;
    _showLabels = widget.group?.showLabels ?? true; // <-- ADDED
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
      notifier.createGroup(
        name: name,
        iconName: _selectedIconName,
        showLabels: _showLabels, // <-- ADDED
      );
    } else {
      notifier.updateGroup(
        widget.group!.id,
        newName: name,
        newIconName: _selectedIconName,
        newShowLabels: _showLabels, // <-- ADDED
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
          // --- ADDED WIDGET ---
          SwitchListTile(
            title: const Text('Show Command Labels'),
            value: _showLabels,
            onChanged: (value) {
              setState(() {
                _showLabels = value;
              });
            },
            contentPadding: EdgeInsets.zero,
          ),
          // --------------------
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
