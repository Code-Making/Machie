import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../app/app_notifier.dart';
import '../command/command_notifier.dart';
import '../editor/plugins/editor_plugin_registry.dart';
import '../explorer/explorer_plugin_registry.dart';
import '../project/project_type_handler_registry.dart';
import 'setting_override_widget.dart';
import 'settings_notifier.dart';
import '../project/project_settings_notifier.dart';
import '../project/project_type_handler.dart';
import '../project/project_settings_models.dart';

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
    final explorerPlugins = ref.watch(explorerRegistryProvider);
    final settings = ref.watch(settingsProvider);
    final generalSettings =
        settings.pluginSettings[GeneralSettings] as GeneralSettings?;
    final activePlugin = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab?.plugin,
      ),
    );
    
    final currentProject = ref.watch(appNotifierProvider).value?.currentProject;
    final projectTypeHandler = currentProject != null
        ? ref.watch(projectTypeHandlerRegistryProvider)[
            currentProject.metadata.projectTypeId]
        : null;

    final pluginsWithSettings =
        allPlugins.where((p) => p.settings != null).toList();
    if (activePlugin != null && pluginsWithSettings.contains(activePlugin)) {
      pluginsWithSettings.remove(activePlugin);
      //pluginsWithSettings.insert(0, activePlugin);
    }
    final explorerPluginsWithSettings =
      explorerPlugins.where((p) => p.settings != null).toList();


return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('Command Customization'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pushNamed(context, '/command-settings'),
        ),
        if (generalSettings != null) 
        _ExpandableSettingsList(
          title: 'General Settings',
          items: [_GeneralSettingsCard(settings: generalSettings)],
        ),
        if (projectTypeHandler?.projectTypeSettings != null && currentProject?.settings?.typeSpecificSettings != null)
          _ProjectSpecificSettingsCard(
            handler: projectTypeHandler!,
            settings: currentProject!.settings!.typeSpecificSettings!,
          ),
        _ExpandableSettingsList(
          title: 'Explorer Plugins',
          items: explorerPluginsWithSettings
              .where((plugin) => settings.explorerPluginSettings[plugin.id] != null)
              .map(
                (plugin) => _ExplorerPluginSettingsCard(
                  plugin: plugin,
                  settings: settings.explorerPluginSettings[plugin.id]!
                      as ExplorerPluginSettings,
                ),
              )
              .toList(),
        ),
        _ExpandableSettingsList(
          title: 'Editor Plugins',
          items: pluginsWithSettings
              .map(
                (plugin) => _PluginSettingsCard(
                  plugin: plugin,
                  settings: settings.pluginSettings[plugin.settings.runtimeType]!
                      as PluginSettings,
                ),
              )
              .toList(),
        ),
        if (activePlugin != null)
          _PluginSettingsCard(
            expanded: true,
            plugin: activePlugin,
            settings: settings.pluginSettings[activePlugin.settings.runtimeType]!
                as PluginSettings,
          ),
      ],
    );
  }
}

class _ExpandableSettingsList extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const _ExpandableSettingsList({
    Key? key,
    required this.title,
    required this.items,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title),
      children: items,
    );
  }
}

class _GeneralSettingsCard extends ConsumerWidget {
  final GeneralSettings settings; // This is the global instance.
  const _GeneralSettingsCard({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        // A SINGLE SettingOverrideWidget wraps the entire group of settings.
        child: SettingOverrideWidget(
          globalSetting: settings,
          childBuilder: (context, effectiveSetting, onChanged) {
            // The builder provides the correct settings object (global or override)
            // and the correct update function.
            final currentSettings = effectiveSetting as GeneralSettings;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _buildAccentColorPicker(
                  context,
                  currentSettings,
                  (newSettings) => onChanged(newSettings),
                ),
                const Divider(height: 32),
                Text('File Explorer', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _buildHiddenFilesSwitch(
                  context,
                  currentSettings,
                  (newSettings) => onChanged(newSettings),
                ),
                const Divider(height: 32),
                Text('Fullscreen Mode', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _buildFullscreenToggles(
                  context,
                  currentSettings,
                  (newSettings) => onChanged(newSettings),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Helper methods are now plain functions, not widgets. They are fully "dumb".
  Widget _buildAccentColorPicker(
    BuildContext context,
    GeneralSettings effectiveSettings,
    void Function(GeneralSettings) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Accent Color', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: kAccentColors.entries.map((entry) {
            final color = entry.value;
            final isSelected = effectiveSettings.accentColorValue == color.value;
            return GestureDetector(
              onTap: () =>
                  onChanged(effectiveSettings.copyWith(accentColorValue: color.value)),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
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

  Widget _buildHiddenFilesSwitch(
    BuildContext context,
    GeneralSettings effectiveSettings,
    void Function(GeneralSettings) onChanged,
  ) {
    return SwitchListTile(
      title: const Text('Show Hidden Files'),
      subtitle: const Text(
        'Displays files and folders starting with a dot (e.g., .git)',
      ),
      value: effectiveSettings.showHiddenFiles,
      onChanged: (value) =>
          onChanged(effectiveSettings.copyWith(showHiddenFiles: value)),
    );
  }

  Widget _buildFullscreenToggles(
    BuildContext context,
    GeneralSettings effectiveSettings,
    void Function(GeneralSettings) onChanged,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          title: const Text('Hide App Bar'),
          value: effectiveSettings.hideAppBarInFullScreen,
          onChanged: (value) =>
              onChanged(effectiveSettings.copyWith(hideAppBarInFullScreen: value)),
        ),
        SwitchListTile(
          title: const Text('Hide Tab Bar'),
          value: effectiveSettings.hideTabBarInFullScreen,
          onChanged: (value) =>
              onChanged(effectiveSettings.copyWith(hideTabBarInFullScreen: value)),
        ),
        SwitchListTile(
          title: const Text('Hide Bottom Toolbar'),
          value: effectiveSettings.hideBottomToolbarInFullScreen,
          onChanged: (value) =>
              onChanged(effectiveSettings.copyWith(hideBottomToolbarInFullScreen: value)),
        ),
      ],
    );
  }
}

class _ProjectSpecificSettingsCard extends ConsumerWidget {
  final ProjectTypeHandler handler;
  final ProjectSettings settings;

  const _ProjectSpecificSettingsCard({
    required this.handler,
    required this.settings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(projectSettingsProvider.notifier);
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Icon(handler.icon),
            const SizedBox(width: 12),
            Text(
              '${handler.name} Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        subtitle: const Text('These settings are specific to this project'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: handler.buildProjectTypeSettingsUI(
              settings,
              (newSettings) => notifier.updateProjectTypeSettings(newSettings),
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginSettingsCard extends ConsumerWidget {
  final EditorPlugin plugin;
  final PluginSettings settings;
  final bool expanded;

  const _PluginSettingsCard({required this.plugin, required this.settings, this.expanded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        title: Row(
          children: [
            plugin.icon,
            const SizedBox(width: 12),
            Text(
              plugin.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SettingOverrideWidget(
              globalSetting: settings,
              childBuilder: (context, effectiveSetting, onChanged) {
                return plugin.buildSettingsUI(
                  effectiveSetting as PluginSettings,
                  (newSettings) => onChanged(newSettings),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplorerPluginSettingsCard extends ConsumerWidget {
  final ExplorerPlugin plugin;
  final ExplorerPluginSettings settings;

  const _ExplorerPluginSettingsCard({required this.plugin, required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(plugin.icon),
            const SizedBox(width: 12),
            Text(
              plugin.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SettingOverrideWidget(
              globalSetting: settings,
              childBuilder: (context, effectiveSetting, onChanged) {
                return plugin.buildSettingsUI(
                  effectiveSetting as ExplorerPluginSettings,
                  (newSettings) => onChanged(newSettings),
                );
              },
            ),
          ),
        ],
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
    return ExpansionTile(
      leading: group.finalIcon, // Use the new getter for the icon
      title: Text(group.label),
      initiallyExpanded: true,
      // --- START: MODIFIED TRAILING WIDGETS ---
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The edit button now handles both user and plugin groups
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: group.isDeletable ? 'Edit Group' : 'Customize Group',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => GroupEditorDialog(ref: ref, group: group),
            ),
          ),
          // Only show delete button for user-created groups
          if (group.isDeletable)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () =>
                  ref.read(commandProvider.notifier).deleteGroup(group.id),
            ),
        ],
      ),
      // --- END: MODIFIED TRAILING WIDGETS ---
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
    
    final originalPluginGroups = notifier.pluginDefinedGroups;

    final currentPosition = state.availablePositions.firstWhereOrNull(
      (p) => p.id == positionId,
    );
    final currentGroup = state.commandGroups[positionId];
    
    return Column(
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemIds.length,
          itemBuilder: (ctx, index) {
            final itemId = itemIds[index];
            final Widget itemWidget;
            
            bool canBeRemoved = true;
            if (positionId == AppCommandPositions.hidden.id) {
              canBeRemoved = false;
            } else if (currentPosition?.mandatoryCommands.contains(itemId) ?? false) {
              canBeRemoved = false;
            } else if (currentGroup != null && !currentGroup.isDeletable) {
              // We are inside a plugin group. Check if the item is a default one.
              final originalGroupDef = originalPluginGroups[currentGroup.id];
              if (originalGroupDef?.commandIds.contains(itemId) ?? false) {
                // This item was part of the original plugin definition, so it can't be removed.
                canBeRemoved = false;
              }
              // Otherwise, it's a user-added item, and canBeRemoved remains true.
            }

            if (state.commandGroups.containsKey(itemId)) {
              final group = state.commandGroups[itemId]!;
              itemWidget = ListTile(
                key: ValueKey(group.id),
                leading: const Icon(Icons.drag_handle),
                title: Row(
                  children: [
                    group.finalIcon,
                    const SizedBox(width: 12),
                    Text(
                      group.label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                trailing: !canBeRemoved
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
                key: ValueKey(command!.id + positionId),
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
                trailing: !canBeRemoved
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.redAccent,
                        ),
                        tooltip: 'Remove from this list',
                        onPressed: () => notifier.removeItemFromList(
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
  late bool _showLabels; 
  late bool _isPluginGroup;

  @override
  void initState() {
    super.initState();
    _isPluginGroup = !(widget.group?.isDeletable ?? true);
    _nameController = TextEditingController(text: widget.group?.label ?? '');
    _selectedIconName =
        widget.group?.iconName ?? CommandIcon.availableIcons.keys.first;
    _showLabels = widget.group?.showLabels ?? true;
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
        showLabels: _showLabels, 
      );
    } else {
      notifier.updateGroup(
        widget.group!.id,
        newName: name,
        newIconName: _selectedIconName,
        newShowLabels: _showLabels, 
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
            autofocus: !_isPluginGroup,
            readOnly: _isPluginGroup,
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: widget.group?.finalIcon ?? CommandIcon.getIcon(_selectedIconName),
            title: const Text('Group Icon'),
            trailing: _isPluginGroup ? null : const Icon(Icons.arrow_drop_down),
            onTap: _isPluginGroup
                ? null
                : () async {
              final String? newIcon = await showDialog(
                context: context,
                builder: (_) => const IconPickerDialog(),
              );
              if (newIcon != null) {
                setState(() => _selectedIconName = newIcon);
              }
            },
          ),
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
