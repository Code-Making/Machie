import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../project/project_models.dart';
import '../../models/editor_plugin_models.dart';
import '../../models/editor_tab_models.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../settings/settings_notifier.dart';

import 'termux_terminal_models.dart';
import 'termux_hot_state.dart';
import 'termux_hot_state_adapter.dart';
import 'widgets/termux_terminal_widget.dart';
import 'widgets/termux_settings_widget.dart';
import '../../../project/project_settings_notifier.dart';
import '../../../command/command_widgets.dart';

class TermuxTerminalPlugin extends EditorPlugin {
  static const String pluginId = 'com.machine.termux_terminal';
  static const String hotStateId = 'com.machine.termux_terminal_state';
  static const String termuxSessionUri = 'internal://termux.terminal';

  static const CommandPosition termuxToolbar = AppCommandPositions.pluginToolbar;

  @override
  String get id => pluginId;

  @override
  String get name => 'Termux Console';

  @override
  Widget get icon => const Icon(Icons.terminal);

  @override
  int get priority => 50;

  // IMPORTANT: This is the initial default. Updates flow through the SettingsNotifier.
  @override
  final PluginSettings settings = TermuxTerminalSettings();

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  String? get hotStateDtoType => hotStateId;

  @override
  Type? get hotStateDtoRuntimeType => TermuxHotStateDto;

  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => TermuxHotStateAdapter();

  @override
  List<CommandPosition> getCommandPositions() {
    return [AppCommandPositions.pluginToolbar];
  }

  TermuxTerminalWidgetState? _getActiveTerminalState(WidgetRef ref) {
    final activeTab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (activeTab is TermuxTerminalTab) {
      return activeTab.editorKey.currentState;
    }
    return null;
  }

  @override
  List<Command> getCommands() {
    // NOTE: This runs ONCE at startup. 
    // Shortcuts added here will appear as buttons.
    // Changes to the shortcut list require an app restart to appear as *buttons*.
    final termuxSettings = settings as TermuxTerminalSettings;
    
    final standardCommands = [
       BaseCommand(
        id: 'termux_esc',
        label: 'Esc',
        icon: const Icon(Icons.keyboard_return),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b'),
      ),
      BaseCommand(
        id: 'termux_tab',
        label: 'Tab',
        icon: const Icon(Icons.keyboard_tab),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\t'),
      ),
      BaseCommand(
        id: 'termux_ctrl',
        label: 'Ctrl',
        icon: const Icon(Icons.keyboard_control_key),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.toggleCtrl(),
      ),
      BaseCommand(
        id: 'termux_alt',
        label: 'Alt',
        icon: const Icon(Icons.alt_route),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.toggleAlt(),
      ),
      BaseCommand(
        id: 'termux_arrows',
        label: 'Arrows',
        icon: const Icon(Icons.open_with),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async {
           // Small popup for arrows if space is tight, or just individual buttons
           // Here we implement individual buttons in the list below for simplicity
        }
      ),
       BaseCommand(
        id: 'termux_arrow_up',
        label: 'Up',
        icon: const Icon(Icons.arrow_upward),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b[A'),
      ),
      BaseCommand(
        id: 'termux_arrow_down',
        label: 'Down',
        icon: const Icon(Icons.arrow_downward),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b[B'),
      ),
       BaseCommand(
        id: 'termux_arrow_left',
        label: 'Left',
        icon: const Icon(Icons.arrow_back),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b[D'),
      ),
       BaseCommand(
        id: 'termux_arrow_right',
        label: 'Right',
        icon: const Icon(Icons.arrow_forward),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x1b[C'),
      ),
      BaseCommand(
        id: 'termux_ctrl_c',
        label: 'Ctrl+C',
        icon: const Icon(Icons.cancel), 
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x03'),
      ),
      BaseCommand(
        id: 'termux_ctrl_x',
        label: 'Ctrl+X',
        icon: const Icon(Icons.cut),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async => _getActiveTerminalState(ref)?.sendRawInput('\x18'),
      ),
    ];

    // 2. Dynamic Commands (Initial Load)
    final customCommands = termuxSettings.customShortcuts.asMap().entries.map((entry) {
      final index = entry.key;
      final shortcut = entry.value;
      
      return BaseCommand(
        id: 'termux_custom_$index',
        label: shortcut.label,
        icon: Icon(TerminalShortcut.resolveIcon(shortcut.iconName)),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async {
          _getActiveTerminalState(ref)?.sendRawInput('${shortcut.command}\r');
        },
      );
    }).toList();

    // 3. The "Run Shortcut..." command (Dynamic Picker)
    // This allows accessing new shortcuts without restarting the app.
    final pickerCommand = BaseCommand(
        id: 'termux_run_shortcut',
        label: 'Run Shortcut...',
        icon: const Icon(Icons.list_alt),
        sourcePlugin: pluginId,
        defaultPositions: [termuxToolbar],
        execute: (ref) async {
           final settings = ref.read(effectiveSettingsProvider).pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings?;
           if (settings == null) return;
           
           final terminal = _getActiveTerminalState(ref);
           if (terminal == null) return;
           
           // Show simple dialog
           final context = ref.read(navigatorKeyProvider).currentContext;
           if (context == null) return;
           
           await showModalBottomSheet(
             context: context, 
             builder: (ctx) => SizedBox(
               height: 300,
               child: ListView(
                 children: settings.customShortcuts.map((s) => ListTile(
                   leading: Icon(TerminalShortcut.resolveIcon(s.iconName)),
                   title: Text(s.label),
                   subtitle: Text(s.command),
                   onTap: () {
                     Navigator.pop(ctx);
                     terminal.sendRawInput('${s.command}\r');
                   },
                 )).toList(),
               ),
             )
           );
        },
    );

    return [...standardCommands, ...customCommands, pickerCommand];
  }

  @override
  List<Command> getAppCommands() {
    return [
      BaseCommand(
        id: 'open_termux_terminal',
        label: 'New Terminal',
        icon: const Icon(Icons.terminal),
        sourcePlugin: 'App',
        defaultPositions: [AppCommandPositions.appBar],
        canExecute: (ref) {
          return ref.watch(appNotifierProvider).value?.currentProject != null;
        },
        execute: (ref) async {
          final notifier = ref.read(appNotifierProvider.notifier);
          final terminalFile = InternalAppFile(
            uri: termuxSessionUri,
            name: 'Termux Session',
          );
          await notifier.openFileInEditor(
            terminalFile,
            explicitPlugin: this,
          );
        },
      ),
    ];
  }

  @override
  bool supportsFile(DocumentFile file) => file.uri == termuxSessionUri;

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    String? history;
    String? cachedWd;

    if (initData.hotState is TermuxHotStateDto) {
      final state = initData.hotState as TermuxHotStateDto;
      cachedWd = state.workingDirectory;
      history = state.terminalHistory;
    }

    return TermuxTerminalTab(
      plugin: this,
      initialWorkingDirectory: cachedWd ?? '', 
      initialHistory: history,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return TermuxTerminalWidget(
      key: (tab as TermuxTerminalTab).editorKey, 
      tab: tab
    );
  }

  @override
  Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) {
    return TermuxSettingsWidget(
      settings: settings as TermuxTerminalSettings,
      onChanged: (newSettings) => onChanged(newSettings as PluginSettings),
    );
  }
  
  @override
  Widget buildToolbar(WidgetRef ref) {
    return const BottomToolbar();
  }
}