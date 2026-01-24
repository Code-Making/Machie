// FILE: lib/editor/plugins/termux_terminal/widgets/termux_terminal_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../services/termux_bridge_service.dart';
import '../termux_terminal_models.dart';
import '../../../../settings/settings_notifier.dart';
import '../../../../logs/logs_provider.dart';
import '../../../models/editor_tab_models.dart';

// A simple light theme for the terminal
const _lightTheme = TerminalTheme(
  cursor: Colors.black,
  selection: Color(0x40000000),
  foreground: Colors.black,
  background: Colors.white,
  black: Color(0xff000000),
  red: Color(0xffcd3131),
  green: Color(0xff0dbc79),
  yellow: Color(0xffe5e510),
  blue: Color(0xff2472c8),
  magenta: Color(0xffbc3fbc),
  cyan: Color(0xff11a8cd),
  white: Color(0xffe5e5e5),
  brightBlack: Color(0xff666666),
  brightRed: Color(0xfff14c4c),
  brightGreen: Color(0xff23d186),
  brightYellow: Color(0xfff5f543),
  brightBlue: Color(0xff3b8ff9),
  brightMagenta: Color(0xffd670d6),
  brightCyan: Color(0xff29b8db),
  brightWhite: Color(0xffe5e5e5),
  // Added required search parameters
  searchHitBackground: Color(0x40e5e510),
  searchHitBackgroundCurrent: Color(0xffe5e510),
  searchHitForeground: Colors.black,
);

class TermuxTerminalWidget extends EditorWidget {
  @override
  final TermuxTerminalTab tab;

  const TermuxTerminalWidget({
    required GlobalKey<TermuxTerminalWidgetApi> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  TermuxTerminalWidgetState createState() => TermuxTerminalWidgetState();
}

class TermuxTerminalWidgetState extends EditorWidgetState<TermuxTerminalWidget>
    implements TermuxTerminalWidgetApi {
  late final Terminal _terminal;
  StreamSubscription<String>? _outputSubscription;
  late TermuxBridgeService _bridgeService;

  @override
  void init() {
    _terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) {
        sendRawInput(data);
      },
    );
    _initTerminalSession();
  }

  @override
  void onFirstFrameReady() {
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  Future<void> _initTerminalSession() async {
    _bridgeService = ref.read(termuxBridgeServiceProvider);
    await _bridgeService.initialize();

    _outputSubscription = _bridgeService.outputStream.listen(
      (data) {
        _terminal.write(data);
      },
      onError: (e) {
        _terminal.write('\r\n[STREAM ERROR]: $e\r\n');
      },
    );

    final settings = ref
        .read(effectiveSettingsProvider)
        .pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings?;

    await _bridgeService.executeCommand(
      command: settings?.shellCommand ?? 'bash',
      workingDirectory: widget.tab.initialWorkingDirectory,
      shell: settings?.shellCommand ?? 'bash',
    );
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    // _terminal.dispose() is not available in some versions of xterm.dart;
    // The Terminal instance will be garbage collected with the widget.
    super.dispose();
  }

  @override
  void sendRawInput(String data) {
    ref.read(talkerProvider).warning(
          '[TermuxTerminal] sendRawInput called, but two-way communication is not yet implemented in the bridge.',
        );
    // TODO: Implement mechanism to send input to Termux
  }

  @override
  Widget build(BuildContext context) {
    // Keep provider alive
    ref.watch(termuxBridgeServiceProvider);

    final settings = ref.watch(
      effectiveSettingsProvider.select(
        (s) =>
            s.pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings,
      ),
    );

    return TerminalView(
      _terminal,
      autofocus: true,
      backgroundOpacity: 1.0,
      theme: settings.useDarkTheme ? TerminalThemes.defaultTheme : _lightTheme,
      textStyle: TerminalStyle(
        fontFamily: settings.fontFamily,
        fontSize: settings.fontSize,
      ),
    );
  }

  @override
  Future<EditorContent> getContent() async =>
      EditorContentString(_terminal.buffer.toString());

  @override
  void onSaveSuccess(String newHash) {}

  @override
  void redo() {}

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    return null;
  }

  @override
  void syncCommandContext() {}

  @override
  void undo() {}
}

abstract class TermuxTerminalWidgetApi
    extends EditorWidgetState<TermuxTerminalWidget> {
  void sendRawInput(String data);
}