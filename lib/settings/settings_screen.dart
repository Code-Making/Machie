// lib/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plugins/plugin_models.dart';
import '../plugins/plugin_registry.dart';
import '../command/command_models.dart';
import '../command/command_notifier.dart';
import 'settings_notifier.dart';

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

    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('Command Customization'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pushNamed(context, '/command-settings'),
        ),
        ...plugins
            .where((p) => p.settings != null)
            .map(
              (plugin) => _PluginSettingsCard(
                plugin: plugin,
                settings: settings.pluginSettings[plugin.settings.runtimeType]!,
              ),
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
                Text(plugin.name, style: Theme.of(context).textTheme.titleLarge),
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
        onPressed: () => showDialog(
            context: context, builder: (_) => GroupEditorDialog(ref: ref)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          _buildSection(context, ref, 'App Bar', 'appBar', state.appBarOrder),
          _buildSection(
              context, ref, 'Plugin Toolbar', 'pluginToolbar', state.pluginToolbarOrder),
          ...state.commandGroups.values
              .map((group) => _buildGroupSection(context, ref, group)),
          _buildSection(
              context, ref, 'Hidden Commands', 'hidden', state.hiddenOrder),
        ],
      ),
    );
  }

  Widget _buildGroupSection(
      BuildContext context, WidgetRef ref, CommandGroup group) {
    return ExpansionTile(
      leading: group.icon,
      title: Text(group.label),
      initiallyExpanded: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => showDialog(
                context: context,
                builder: (_) => GroupEditorDialog(ref: ref, group: group)),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: () =>
                ref.read(commandProvider.notifier).deleteGroup(group.id),
          ),
        ],
      ),
      children: [
        _buildReorderableList(context, ref, group.commandIds, listId: group.id)
      ],
    );
  }

  Widget _buildSection(BuildContext context, WidgetRef ref, String title,
      String listId, List<String> itemIds) {
    return ExpansionTile(
      title: Text(title),
      initiallyExpanded: true,
      children: [
        _buildReorderableList(context, ref, itemIds, listId: listId)
      ],
    );
  }

  Widget _buildReorderableList(BuildContext context, WidgetRef ref,
      List<String> itemIds, {required String listId}) {
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
            if (state.commandGroups.containsKey(itemId)) {
              final group = state.commandGroups[itemId]!;
              return _buildGroupItem(context, ref, group, listId);
            } else {
              final sources = state.commandSources[itemId];
              if (sources == null || sources.isEmpty) {
                return ListTile(
                    key: ValueKey(itemId),
                    title: Text('Error: Unknown command "$itemId"'));
              }
              return _buildCommandItem(context, ref, itemId, sources, listId: listId);
            }
          },
          onReorder: (oldIndex, newIndex) {
            notifier.reorderItemInList(
                listId: listId, oldIndex: oldIndex, newIndex: newIndex);
          },
        ),
        if (listId != 'hidden')
          Padding(
            padding: const EdgeInsets.only(right: 16.0, bottom: 8.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add command to this section',
                onPressed: () => showDialog(
                    context: context,
                    builder: (_) =>
                        AddCommandDialog(ref: ref, toListId: listId)),
              ),
            ),
          )
      ],
    );
  }

  Widget _buildGroupItem(BuildContext context, WidgetRef ref, CommandGroup group, String currentListId) {
     return ListTile(
        key: ValueKey(group.id),
        leading: const Icon(Icons.drag_handle),
        title: Row(
        children: [
          group.icon,
          const SizedBox(width: 12),
          Expanded(child: Text(group.label, style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showGroupPositionMenu(context, ref, group, currentListId),
      ),
    );
  }

  Widget _buildCommandItem(BuildContext context, WidgetRef ref,
      String commandId, Set<String> sources, {required String listId}) {
    final notifier = ref.read(commandProvider.notifier);
    final command = notifier.getCommand(commandId, sources.first);
    if (command == null)
      return ListTile(
          key: ValueKey(commandId),
          title: Text('Error: Unknown command "$commandId"'));

    return ListTile(
      key: ValueKey(commandId),
      leading: const Icon(Icons.drag_handle),
      title: Row(
        children: [
          command.icon,
          const SizedBox(width: 12),
          Expanded(child: Text(command.label, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: sources.length > 1 ? Text('From: ${sources.join(', ')}') : null,
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent,),
        tooltip: 'Remove from this list (move to Hidden)',
        onPressed: () =>
            notifier.removeCommandFromList(itemId: commandId, fromListId: listId),
      ),
    );
  }
  
  void _showGroupPositionMenu(BuildContext context, WidgetRef ref, CommandGroup group, String fromListId) {
    final notifier = ref.read(commandProvider.notifier);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move "${group.label}" Group to...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('App Bar'), onTap: () {
                notifier.moveItem(itemId: group.id, fromListId: fromListId, toListId: 'appBar', newIndex: -1);
                Navigator.pop(ctx);
            }),
            ListTile(title: const Text('Plugin Toolbar'), onTap: () {
                notifier.moveItem(itemId: group.id, fromListId: fromListId, toListId: 'pluginToolbar', newIndex: -1);
                Navigator.pop(ctx);
            }),
          ],
        ),
      ),
    );
  }
}

// --- Dialogs ---

class AddCommandDialog extends ConsumerStatefulWidget {
    final WidgetRef ref;
    final String toListId;
    const AddCommandDialog({super.key, required this.ref, required this.toListId});

    @override
    ConsumerState<AddCommandDialog> createState() => _AddCommandDialogState();
}

class _AddCommandDialogState extends ConsumerState<AddCommandDialog> {
    final _searchController = TextEditingController();
    String _query = '';

    @override
    void initState() {
        super.initState();
        _searchController.addListener(() => setState(() => _query = _searchController.text.toLowerCase()));
    }
    
    @override
    void dispose() {
        _searchController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        final notifier = widget.ref.read(commandProvider.notifier);
        // Get unique commands by ID
        final allCommands = { for (var cmd in notifier.allRegisteredCommands) cmd.id: cmd }.values.toList();
        
        final filteredCommands = allCommands.where((cmd) => cmd.label.toLowerCase().contains(_query)).toList();

        return AlertDialog(
            title: const Text('Add Command'),
            content: SizedBox(
                width: double.maxFinite,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(labelText: 'Search commands...'),
                            autofocus: true,
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                            child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredCommands.length,
                                itemBuilder: (context, index) {
                                    final command = filteredCommands[index];
                                    return ListTile(
                                        leading: command.icon,
                                        title: Text(command.label),
                                        subtitle: Text(command.sourcePlugin),
                                        onTap: () {
                                            notifier.addCommandToList(itemId: command.id, toListId: widget.toListId);
                                            Navigator.of(context).pop();
                                        },
                                    );
                                },
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
    _selectedIconName = widget.group?.iconName ?? CommandIcon.availableIcons.keys.first;
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
        notifier.updateGroup(widget.group!.id, newName: name, newIconName: _selectedIconName);
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
                final String? newIcon = await showDialog(context: context, builder: (_) => const IconPickerDialog());
                if (newIcon != null) {
                    setState(() => _selectedIconName = newIcon);
                }
            },
          )
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
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
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
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