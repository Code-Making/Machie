import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../termux_hot_state.dart';
import '../../../../settings/settings_notifier.dart';
import '../../../../logs/logs_provider.dart';
import '../termux_terminal_models.dart';
import '../services/termux_bridge_service.dart';
import '../../../models/editor_tab_models.dart';

// --- ADDED: Custom Input Handler ---
class TermuxInputHandler implements TerminalInputHandler {
  final TerminalInputHandler _delegate = defaultInputHandler;
  
  bool ctrlActive = false;
  bool altActive = false;

  @override
  String? call(TerminalKeyboardEvent event) {
    // Apply our virtual modifiers to the event
    final effectiveEvent = event.copyWith(
      ctrl: event.ctrl || ctrlActive,
      alt: event.alt || altActive,
    );
    
    // Pass to the default handler (which handles key mapping)
    return _delegate(effectiveEvent);
  }
}

abstract class TermuxTerminalWidgetState extends EditorWidgetState<TermuxTerminalWidget> {
  void sendRawInput(String data);
  void toggleCtrl();
  void toggleAlt();
  bool get isCtrlActive;
  bool get isAltActive;
}

class TermuxTerminalWidget extends EditorWidget {
  @override
  final TermuxTerminalTab tab;

  const TermuxTerminalWidget({
    required super.key,
    required this.tab,
  }) : super(tab: tab);

  @override
  _TermuxTerminalWidgetState createState() => _TermuxTerminalWidgetState();
}

class _TermuxTerminalWidgetState extends TermuxTerminalWidgetState {
  late final Terminal _terminal;
  late final TermuxBridgeService _bridge;
  late final TermuxInputHandler _inputHandler; // ADDED
  StreamSubscription? _bridgeSubscription;

  @override
  void init() {
    super.init();
    
    // Initialize our custom handler
    _inputHandler = TermuxInputHandler();

    _terminal = Terminal(
      maxLines: 10000,
      inputHandler: _inputHandler, // Register the handler
    );
    
    _bridge = ref.read(termuxBridgeServiceProvider);
    
    _bridgeSubscription = _bridge.outputStream.listen((data) {
      if (mounted) {
        _terminal.write(data);
      }
    });

    _terminal.onOutput = _onTerminalOutput;

    if (widget.tab.initialHistory != null && widget.tab.initialHistory!.isNotEmpty) {
      _terminal.write(widget.tab.initialHistory!);
    }
  }

  @override
  void onFirstFrameReady() {
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
    _startTermuxSession();
  }
  
  void _startTermuxSession() {
    final settings = ref.read(settingsProvider.select(
      (s) => s.pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings,
    ));

    _bridge.executeCommand(
      workingDirectory: widget.tab.initialWorkingDirectory,
      shell: settings.shellCommand,
    ).catchError((e, st) {
      final errorMessage = "\r\n\x1b[31mError starting Termux session: $e\x1b[0m\r\n";
      _terminal.write(errorMessage);
      ref.read(talkerProvider).handle(e, st, "Failed to start Termux session");
    });
  }

  void _onTerminalOutput(String data) {
    _bridge.write(data);
    
    // Optional: Reset modifiers after a key is sent (Sticky behavior)
    // If you want "Lock" behavior, remove these lines.
    // We'll assume Sticky behavior for better mobile UX.
    if (_inputHandler.ctrlActive || _inputHandler.altActive) {
      setState(() {
        _inputHandler.ctrlActive = false;
        _inputHandler.altActive = false;
      });
    }
  }

  @override
  void sendRawInput(String data) {
    _terminal.textInput(data);
  }

  // --- ADDED: Toggle Implementation ---
  @override
  void toggleCtrl() {
    setState(() {
      _inputHandler.ctrlActive = !_inputHandler.ctrlActive;
    });
  }

  @override
  void toggleAlt() {
    setState(() {
      _inputHandler.altActive = !_inputHandler.altActive;
    });
  }

  @override
  bool get isCtrlActive => _inputHandler.ctrlActive;

  @override
  bool get isAltActive => _inputHandler.altActive;
  // ------------------------------------

  @override
  void dispose() {
    _bridgeSubscription?.cancel();
    super.dispose();
  }

  @override
  Future<EditorContent> getContent() async {
    final buffer = _terminal.buffer.getText();
    return EditorContentString(buffer);
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    final buffer = await getContent() as EditorContentString;
    return TermuxHotStateDto(
      workingDirectory: widget.tab.initialWorkingDirectory,
      terminalHistory: buffer.content,
    );
  }

  @override
  void onSaveSuccess(String newHash) {}
  @override
  void redo() {}
  @override
  void undo() {}
  @override
  void syncCommandContext() {}

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider.select(
      (s) => s.pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings,
    ));

    const lightTheme = TerminalTheme(
      cursor: Color(0xFF000000),
      selection: Color(0xFFB0B0B0),
      foreground: Color(0xFF000000),
      background: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFFA0),
      searchHitBackgroundCurrent: Color(0xFFFFFF00),
      searchHitForeground: Color(0xFF000000),
      black: Color(0xFF000000),
      red: Color(0xFFC51E14),
      green: Color(0xFF1DC121),
      yellow: Color(0xFFC7C329),
      blue: Color(0xFF0A2FC4),
      magenta: Color(0xFFC8399F),
      cyan: Color(0xFF20C5C6),
      white: Color(0xFFC7C7C7),
      brightBlack: Color(0xFF686868),
      brightRed: Color(0xFFFD6F6B),
      brightGreen: Color(0xFF67F86F),
      brightYellow: Color(0xFFFFFA72),
      brightBlue: Color(0xFF6A76FB),
      brightMagenta: Color(0xFFFD7CFC),
      brightCyan: Color(0xFF68FDFE),
      brightWhite: Color(0xFFFFFFFF),
    );

    return TerminalView(
      _terminal,
      theme: settings.useDarkTheme ? TerminalThemes.defaultTheme : lightTheme,
      textStyle: TerminalStyle(
        fontFamily: settings.fontFamily,
        fontSize: settings.fontSize,
      ),
      autofocus: true,
    );
  }
}