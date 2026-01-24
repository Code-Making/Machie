// FILE: lib/editor/plugins/termux_terminal/widgets/termux_terminal_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../services/termux_bridge_service.dart';
import '../termux_terminal_models.dart';
import '../../../../settings/settings_notifier.dart';
import '../../../../logs/logs_provider.dart';
import '../widgets/termux_toolbar.dart'; // Ensure this is imported if used
import '../../../models/editor_tab_models.dart'; // For EditorWidgetState

class TermuxTerminalWidget extends EditorWidget {
  @override
  final TermuxTerminalTab tab;

  const TermuxTerminalWidget({
    required GlobalKey<TermuxTerminalWidgetState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  TermuxTerminalWidgetState createState() => TermuxTerminalWidgetState();
}

class TermuxTerminalWidgetState extends EditorWidgetState<TermuxTerminalWidget>
    implements TermuxTerminalWidgetApi {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  StreamSubscription<String>? _outputSubscription;
  late TermuxBridgeService _bridgeService;

  @override
  void init() {
    _terminalController = TerminalController();
    _terminal = Terminal(
      controller: _terminalController,
      maxLines: 10000,
    );
    // Asynchronously initialize the bridge and start the terminal session.
    _initTerminalSession();
  }

  @override
  void onFirstFrameReady() {
     if (!widget.tab.onReady.isCompleted) {
        widget.tab.onReady.complete(this);
      }
  }

  Future<void> _initTerminalSession() async {
    // We can safely read here because the provider will be kept alive by the watch in build().
    _bridgeService = ref.read(termuxBridgeServiceProvider);
    
    // Ensure the server socket is ready before we do anything else.
    await _bridgeService.initialize();

    // Subscribe to the output stream to receive data from Termux.
    _outputSubscription = _bridgeService.outputStream.listen(
      (data) {
        // Write incoming data directly to the xterm widget.
        _terminal.write(data);
      },
      onError: (e) {
        _terminal.write('\r\n[STREAM ERROR]: $e\r\n');
      },
    );

    final settings = ref.read(effectiveSettingsProvider)
        .pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings?;
    
    // Execute the initial shell command to start the interactive session.
    await _bridgeService.executeCommand(
      command: settings?.shellCommand ?? 'bash',
      workingDirectory: widget.tab.initialWorkingDirectory,
      shell: settings?.shellCommand ?? 'bash',
    );
  }

  @override
  void dispose() {
    // Cancel the stream subscription to prevent memory leaks.
    _outputSubscription?.cancel();
    _terminalController.dispose();
    super.dispose();
  }

  @override
  void sendRawInput(String data) {
    ref.read(talkerProvider).warning(
      '[TermuxTerminal] sendRawInput called, but two-way communication is not yet implemented in the bridge.',
    );
    // TODO: Implement a mechanism in TermuxBridgeService to send data back to the active shell process.
    // The current `executeCommand` starts a new process each time. We need a way to write to the stdin
    // of the process started in _initTerminalSession. This typically requires a more advanced
    // setup on the Termux side (e.g., using `socat` for a persistent two-way socket).
  }

  @override
  Widget build(BuildContext context) {
    // This is the crucial part: `ref.watch` ensures that as long as this widget is visible,
    // the TermuxBridgeService provider will not be auto-disposed.
    ref.watch(termuxBridgeServiceProvider);

    final settings = ref.watch(
      effectiveSettingsProvider.select(
        (s) => s.pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings,
      ),
    );

    return TerminalView(
      _terminal,
      controller: _terminalController,
      autofocus: true,
      backgroundOpacity: 1.0,
      theme: settings.useDarkTheme ? TerminalThemes.defaultTheme : TerminalThemes.lightTheme,
      textStyle: TerminalTextStyle(
        fontFamily: settings.fontFamily,
        fontSize: settings.fontSize,
      ),
      onOutput: (data) {
        // This is where user input from the terminal is captured.
        // It needs to be sent back to the running shell in Termux.
        sendRawInput(data);
      },
    );
  }

  // Implementation of abstract methods from EditorWidgetState
  @override
  Future<EditorContent> getContent() async => EditorContentString(_terminal.buffer.toString());

  @override
  void onSaveSuccess(String newHash) {}

  @override
  void redo() {}

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    // This needs to be implemented to save session state if desired
    return null;
  }

  @override
  void syncCommandContext() {}

  @override
  void undo() {}
}

// This abstract class helps with the GlobalKey typing in the plugin.
abstract class TermuxTerminalWidgetApi extends EditorWidgetState<TermuxTerminalWidget> {
  void sendRawInput(String data);
}